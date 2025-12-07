require "faraday"
require "json"
require "thread"
require "openai" # Now used for local LLM interaction

# Load the new services
require_relative "web_search_service"
require_relative "knowledge_base_service"

class EmailSearchService
  class AiSearchError < StandardError; end
  class DailyLimitReached < StandardError; end # Retained for compatibility/error handling structure

  # --- Model and Rate Limiting Configuration ---
  # These configurations are now for the local LLM.
  # TODO: Move these configurations to Rails credentials, application.yml, or a dedicated initializer.
  LLM_BASE_URL = "http://10.0.0.202:8080".freeze
  LLM_MODEL_NAME = "Meta-Llama-3.1-8B-Instruct-Q8_0.guff".freeze
  LLM_API_KEY = "dummy".freeze # Local LLMs typically don't require a real API key

  # Configuration for web search, content fetching, and summarization/extraction
  MAX_URLS_TO_PROCESS = 3 # Number of top search results to fetch and process
  MAX_WEBPAGE_CONTENT_CHARS = 2000 # Max characters from webpage content to send to LLM for summarization/extraction
  SUMMARY_WORD_LIMIT = 150 # Max words for each page summary stored in the knowledge base

  # Rate limiting for the local LLM. While a local server might not have external QPM limits,
  # keeping this structure allows for controlled interaction and prevents overwhelming the local LLM.
  REQUESTS_PER_MINUTE = 60
  REQUEST_INTERVAL = 60.0 / REQUESTS_PER_MINUTE # 1.0 second for 60 QPM (e.g., for local LLM)

  @@current_model_index = 0 # Retained for structural consistency, though only one LLM is used here
  @@last_api_call_start_time = Time.at(0)
  @@daily_limit_reached = false # Retained for error handling structure
  @@mutex = Mutex.new

  def self.current_model
    # Returns the currently configured local LLM
    { name: LLM_MODEL_NAME }
  end

  def self.switch_model
    # With a single local LLM, this method primarily logs a warning.
    Rails.logger.warn "EmailSearchService: Attempted to switch model, but only one local LLM configured: #{LLM_MODEL_NAME}"
  end

  def self.wait_for_rate_limit
    @@mutex.synchronize do
      time_since_last_start = Time.now - @@last_api_call_start_time
      if time_since_last_start < REQUEST_INTERVAL
        sleep(REQUEST_INTERVAL - time_since_last_start)
      end
      @@last_api_call_start_time = Time.now
    end
  end

  def self.reset_daily_limit_flag
    @@mutex.synchronize do
      @@daily_limit_reached = false
      Rails.logger.info "EmailSearchService: Daily limit flag reset (note: local LLM typically doesn't have daily limits)"
    end
  end

  def self.daily_limit_reached?
    @@mutex.synchronize { @@daily_limit_reached }
  end

  def self.mark_daily_limit_reached
    @@mutex.synchronize do
      @@daily_limit_reached = true
      Rails.logger.error "EmailSearchService: Marked daily limit reached (for error handling, not actual external API limits)"
    end
  end

  # --- End Configuration ---

  def initialize(organization, search_provider: :searxng)
    @organization = organization
    @search_provider_class = case search_provider
    when :google
                               GoogleSearchService
    when :searxng
                               WebSearchService
    else
                               raise ArgumentError, "Unknown search_provider: #{search_provider}"
    end

    # Initialize OpenAI client for local LLM interaction.
    @llm_client = OpenAI::Client.new(access_token: LLM_API_KEY, uri_base: LLM_BASE_URL)
  end

  def find_email
    details = find_email_with_details
    details[:email]
  end

  def find_email_with_details
    raise DailyLimitReached, "Service temporarily unavailable due to previous errors" if self.class.daily_limit_reached?

    self.class.wait_for_rate_limit

    Rails.logger.info "EmailSearchService: Initiating email search for #{@organization.name} (ID: #{@organization.id}) using #{@search_provider_class.name}"

    attempts = 0
    begin
      attempts += 1
      search_and_extract_email
    rescue AiSearchError => e
      if e.message.include?("Rate limit") && attempts <= 3
        Rails.logger.warn "EmailSearchService: Retrying LLM call for #{@organization.name} due to suspected rate-like error: #{e.message}"
        self.class.wait_for_rate_limit
        retry
      else
        self.class.mark_daily_limit_reached if e.message.include?("Rate limit")
        Rails.logger.error("EmailSearchService: AI Search Error for organization #{@organization.name} (ID: #{@organization.id}): #{e.message}")
        { email: nil, error: e.message }
      end
    rescue => e
      Rails.logger.error("EmailSearchService: An unexpected error occurred in find_email for #{@organization.name} (ID: #{@organization.id}): #{e.class} - #{e.message}")
      { email: nil, error: e.message }
    end
  end

  private

  def build_web_search_query
    city_state = if @organization.us_address.present?
                   parts = @organization.us_address.split("\n").last&.split(" ")
                   " in #{parts[0..-2].join(" ")}, #{parts.last}" if parts&.length&.>= 2
                 end

    "contact email for \"#{@organization.name}\"#{city_state}"
  end

  # Orchestrates web search, content fetching, and email extraction using the RAG pipeline
  def search_and_extract_email
    web_search_query = build_web_search_query
    Rails.logger.info "EmailSearchService: Performing advanced RAG search using query: '#{web_search_query}'"

    begin
      rag_service = RagSearchService.new(
        web_search_query,
        search_provider_class: @search_provider_class,
        transform: true
      )
      context, _ = rag_service.search_and_synthesize

      if context.blank?
        Rails.logger.info "EmailSearchService: RAG service returned no context. Cannot extract email."
        return { email: nil, web_search_query: web_search_query, context: nil, llm_response: "RAG service returned no context." }
      end

      Rails.logger.debug "EmailSearchService: Sending dense context to LLM for email extraction."
      found_email, llm_response = extract_email_with_llm(context)

      { email: found_email, web_search_query: web_search_query, context: context, llm_response: llm_response }

    rescue RagSearchService::RagSearchError => e
      Rails.logger.error "EmailSearchService: RAG search failed for organization #{@organization.name}: #{e.message}"
      { email: nil, web_search_query: web_search_query, error: "RAG search failed: #{e.message}" }
    end
  end

  # Helper method to summarize text using the local LLM
  def summarize_text_with_llm(client, text, query, word_limit)
    messages = [
      { role: "system", content: "You are a concise summarizer. Summarize the following text, focusing on information relevant to the user's query: '#{query}'. Keep the summary under #{word_limit} words." },
      { role: "user", content: text }
    ]
    response = client.chat(
      parameters: { model: LLM_MODEL_NAME, messages: messages, temperature: 0.1 } # Low temperature for factual summaries
    )
    response.dig("choices", 0, "message", "content") || "Could not summarize content."
  rescue => e
    Rails.logger.error "EmailSearchService: Error during content summarization by LLM: #{e.class} - #{e.message}"
    "Error summarizing content."
  end

  # Helper method to extract email using the local LLM
  def extract_email_with_llm(text_to_analyze)
    state = @organization.us_address.present? ? @organization.us_address.split(",").map(&:strip).find { |part| part.match?(/\b[A-Z]{2}\b/) } : nil
    system_prompt = <<-PROMPT
You are an expert email address extractor. Your task is to find the contact email address for a specific organization from the provided text.

Here is the information about the organization I am looking for:
- Name: #{@organization.name}
- EIN: #{@organization.ein}
- State: #{state || 'Not specified'}

Please find the most relevant email address for this exact organization. Prioritize emails for scholarship inquiries, grant programs, or general contact.

If you find an email that is clearly associated with this organization, return ONLY that email address.
If you cannot find an email address specifically for this organization, return exactly: not_found.
Do not return emails for other organizations, even if they are mentioned in the text.
Do not include any other text or explanation in your response.
PROMPT

    messages = [
      { role: "system", content: system_prompt.strip },
      { role: "user", content: text_to_analyze }
    ]
    response = @llm_client.chat(
      parameters: { model: LLM_MODEL_NAME, messages: messages, temperature: 0.1 } # Low temperature for precise extraction
    )
    email_response_text = response.dig("choices", 0, "message", "content")&.strip

    if email_response_text.blank?
      Rails.logger.warn "EmailSearchService: LLM returned no text content for email extraction."
      return [ nil, nil ]
    end

    Rails.logger.debug "EmailSearchService: Raw LLM email extraction response: #{email_response_text[0..200]}"

    # Clean and validate the LLM's response
    cleaned_email_response = email_response_text.downcase

    # If LLM explicitly says "not_found" or similar
    if cleaned_email_response == "not_found" || cleaned_email_response.include?("not found") || cleaned_email_response.include?("cannot find")
      return [ nil, email_response_text ]
    end

    # Attempt to extract a valid email address using regex from the LLM's response
    email_match = email_response_text.match(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    if email_match
      found_email = email_match[0]
      Rails.logger.info "EmailSearchService: Successfully extracted email '#{found_email}' for #{@organization.name}"
      [ found_email, email_response_text ]
    else
      Rails.logger.warn "EmailSearchService: LLM response did not contain a valid email format after extraction attempt for #{@organization.name}: '#{email_response_text[0..100]}'"
      [ nil, email_response_text ]
    end
  rescue Faraday::ConnectionFailed => e
    raise AiSearchError, "Connection to local LLM server failed: #{e.message}. Ensure LLM server is running at #{LLM_BASE_URL}"
  rescue => e
    Rails.logger.error "EmailSearchService: Error during email extraction by LLM: #{e.class} - #{e.message}"
    [ nil, nil ]
  end
end
