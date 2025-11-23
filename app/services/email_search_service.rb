require 'faraday'
require 'json'
require 'thread'
require 'openai' # Now used for local LLM interaction

# Load the new services
require_relative 'web_search_service'
require_relative 'knowledge_base_service'

class EmailSearchService
  class AiSearchError < StandardError; end
  class DailyLimitReached < StandardError; end # Retained for compatibility/error handling structure

  # --- Model and Rate Limiting Configuration ---
  # These configurations are now for the local LLM.
  # TODO: Move these configurations to Rails credentials, application.yml, or a dedicated initializer.
  LLM_BASE_URL = "http://172.18.48.1:8080".freeze
  LLM_MODEL_NAME = "Meta-Llama-3.1-8B-Instruct-Q6_K.gguf".freeze
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

  def initialize(organization)
    @organization = organization
    # Initialize OpenAI client for local LLM interaction.
    # The API key is often "dummy" or optional for local instances.
    @llm_client = OpenAI::Client.new(access_token: LLM_API_KEY, uri_base: LLM_BASE_URL)
  end

  def find_email
    # Retaining daily limit logic to gracefully handle any server errors from the local LLM
    # that might resemble rate limits or indicate it's temporarily unavailable.
    raise DailyLimitReached, "Service temporarily unavailable due to previous errors" if self.class.daily_limit_reached?

    self.class.wait_for_rate_limit # Wait to respect local LLM call frequency
    
    Rails.logger.info "EmailSearchService: Initiating email search for #{@organization.name} (ID: #{@organization.id})"

    attempts = 0
    begin
      attempts += 1
      search_and_extract_email
    rescue AiSearchError => e
      # For local LLMs, 'Rate limit' might indicate server issues. Retry a few times.
      if e.message.include?("Rate limit") && attempts <= 3
        Rails.logger.warn "EmailSearchService: Retrying LLM call for #{@organization.name} due to suspected rate-like error: #{e.message}"
        self.class.wait_for_rate_limit
        retry
      else
        self.class.mark_daily_limit_reached if e.message.include?("Rate limit") # Mark if persistent error
        Rails.logger.error("EmailSearchService: AI Search Error for organization #{@organization.name} (ID: #{@organization.id}): #{e.message}")
        nil
      end
    rescue => e
      Rails.logger.error("EmailSearchService: An unexpected error occurred in find_email for #{@organization.name} (ID: #{@organization.id}): #{e.class} - #{e.message}")
      nil
    end
  end

  private

  # Constructs a search query for the WebSearchService
  def build_web_search_query
    query_parts = []
    query_parts << "#{@organization.name} scholarship contact email"
    query_parts << "(site:.org OR site:.gov)" # Prioritize .org and .gov domains
    query_parts << @organization.ein if @organization.ein.present?
    # Add website only if it's not a generic placeholder
    if @organization.website_address_txt.present? && !@organization.website_address_txt.match?(/n\/?a/i)
      query_parts << @organization.website_address_txt
    end
    query_parts.join(" ")
  end

  # Orchestrates web search, content fetching, summarization, storage, and email extraction
  def search_and_extract_email
    web_search_query = build_web_search_query
    Rails.logger.debug "EmailSearchService: Performing web search using query: '#{web_search_query}'"

    search_results_raw = WebSearchService.search(web_search_query)

    unless search_results_raw && search_results_raw['results']
      Rails.logger.info "EmailSearchService: No valid web search results found for '#{web_search_query}'"
      return nil
    end

    processed_content_for_llm = []
    urls_processed_count = 0

    # Process top N search results
    search_results_raw['results'].first(MAX_URLS_TO_PROCESS).each do |result|
      url = result['url']
      next unless url

      Rails.logger.debug "EmailSearchService: Fetching content from URL: '#{url}'"
      webpage_content = WebSearchService.fetch_page_content(url)
      
      if webpage_content.nil? || webpage_content.strip.empty?
        Rails.logger.warn "EmailSearchService: No content fetched from #{url}. Skipping processing for this URL."
        next
      end

      # Truncate content for both LLM input and knowledge base storage
      truncated_content_for_llm = webpage_content.slice(0, MAX_WEBPAGE_CONTENT_CHARS) +
                                  (webpage_content.length > MAX_WEBPAGE_CONTENT_CHARS ? "..." : "")

      # Summarize the truncated content using LLM for storage in the knowledge base
      summary_for_kb = summarize_text_with_llm(@llm_client, truncated_content_for_llm, web_search_query, SUMMARY_WORD_LIMIT)
      
      # Store the full webpage content, its summary, and embedding in the knowledge base
      KnowledgeBaseService.store_document(url, webpage_content, summary: summary_for_kb)

      processed_content_for_llm << "Source: #{url}\nContent Snippet:\n#{truncated_content_for_llm}"
      urls_processed_count += 1
    end

    if processed_content_for_llm.empty?
      Rails.logger.info "EmailSearchService: No useful webpage content was processed for email extraction."
      return nil
    end

    # Combine all processed content to provide a rich context to the LLM for email extraction
    combined_processed_text = processed_content_for_llm.join("\n\n---\n\n")

    Rails.logger.debug "EmailSearchService: Sending combined content to LLM for email extraction."
    extract_email_with_llm(combined_processed_text)
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
    messages = [
      { role: "system", content: "You are an expert email address extractor. Given the following text content, find the most relevant contact email address for the organization. Prioritize emails for scholarship inquiries, grant programs, or general contact. If you find an email, return ONLY that email address. If no email is found, return exactly: not_found. Do not include any other text or explanation." },
      { role: "user", content: text_to_analyze }
    ]
    response = @llm_client.chat(
      parameters: { model: LLM_MODEL_NAME, messages: messages, temperature: 0.1 } # Low temperature for precise extraction
    )
    email_response_text = response.dig("choices", 0, "message", "content")&.strip

    if email_response_text.blank?
      Rails.logger.warn "EmailSearchService: LLM returned no text content for email extraction."
      return nil
    end

    Rails.logger.debug "EmailSearchService: Raw LLM email extraction response: #{email_response_text[0..200]}"

    # Clean and validate the LLM's response
    cleaned_email_response = email_response_text.downcase

    # If LLM explicitly says "not_found" or similar
    return nil if cleaned_email_response == 'not_found' || cleaned_email_response.include?('not found') || cleaned_email_response.include?('cannot find')

    # Attempt to extract a valid email address using regex from the LLM's response
    email_match = email_response_text.match(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    if email_match
      found_email = email_match[0]
      Rails.logger.info "EmailSearchService: Successfully extracted email '#{found_email}' for #{@organization.name}"
      return found_email
    else
      Rails.logger.warn "EmailSearchService: LLM response did not contain a valid email format after extraction attempt for #{@organization.name}: '#{email_response_text[0..100]}'".
      nil
    end
  rescue Faraday::ConnectionFailed => e
    raise AiSearchError, "Connection to local LLM server failed: #{e.message}. Ensure LLM server is running at #{LLM_BASE_URL}"
  rescue => e
    Rails.logger.error "EmailSearchService: Error during email extraction by LLM: #{e.class} - #{e.message}"
    nil
  end
end