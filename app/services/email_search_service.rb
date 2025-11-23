require 'faraday'
require 'json'
require 'thread'

class EmailSearchService
  class AiSearchError < StandardError; end
  class DailyLimitReached < StandardError; end

  # --- Model and Rate Limiting Configuration ---
  # Using Gemini 2.5 models which support the google_search tool
  MODELS = [
    { name: 'gemini-2.5-flash' },
    { name: 'gemini-2.0-flash-exp' }
  ].freeze

  REQUESTS_PER_MINUTE = 60
  REQUEST_INTERVAL = 60.0 / REQUESTS_PER_MINUTE # 1.0 second for 60 QPM

  @@current_model_index = 0
  @@last_api_call_start_time = Time.at(0)
  @@daily_limit_reached = false
  @@mutex = Mutex.new

  def self.current_model
    MODELS[@@current_model_index]
  end

  def self.switch_model
    @@mutex.synchronize do
      previous_model_name = current_model[:name]
      @@current_model_index = (@@current_model_index + 1) % MODELS.length
      new_model_name = current_model[:name]
      Rails.logger.warn "EmailSearchService: Switching model from #{previous_model_name} to #{new_model_name} due to rate limiting."
    end
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
      @@current_model_index = 0
      Rails.logger.info "EmailSearchService: Daily limit flag reset, model index reset to 0"
    end
  end

  def self.daily_limit_reached?
    @@mutex.synchronize { @@daily_limit_reached }
  end

  def self.mark_daily_limit_reached
    @@mutex.synchronize do
      @@daily_limit_reached = true
      Rails.logger.error "EmailSearchService: Daily limit reached for all models"
    end
  end

  # --- End Configuration ---

  def initialize(organization)
    @organization = organization
    @api_key = ENV['GEMINI_API_KEY']
  end

  def find_email
    # Check if we've already hit the daily limit
    raise DailyLimitReached, "Daily API limit already reached" if self.class.daily_limit_reached?

    self.class.wait_for_rate_limit
    raise "GEMINI_API_KEY not set" if @api_key.blank?

    Rails.logger.info "EmailSearchService: Searching for email for #{@organization.name}"

    attempts = 0
    begin
      attempts += 1
      search_with_ai
    rescue AiSearchError => e
      if e.message.include?("Rate limit") && attempts < MODELS.length
        self.class.switch_model
        self.class.wait_for_rate_limit
        retry
      elsif e.message.include?("Rate limit") && attempts >= MODELS.length
        # We've tried all models and all are rate limited
        self.class.mark_daily_limit_reached
        raise DailyLimitReached, "All available models have reached their daily limit"
      else
        Rails.logger.error("EmailSearchService: AI Search Error for organization #{@organization.name} (ID: #{@organization.id}): #{e.message}")
        nil
      end
    end
  end

  private

  def search_with_ai
    model_config = self.class.current_model
    model_name = model_config[:name]

    endpoint = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent"

    # Build a comprehensive search prompt that gives the AI maximum context
    prompt_parts = []
    prompt_parts << "Search the web to find a contact email address for this organization:"
    prompt_parts << ""
    prompt_parts << "Organization Name: #{@organization.name}"

    # Add EIN if available - helps with uniqueness
    if @organization.ein.present?
      prompt_parts << "EIN (Tax ID): #{@organization.ein}"
    end

    # Add website if we have it and it's valid
    if @organization.website_address_txt.present? && !@organization.website_address_txt.match?(/n\/?a/i)
      website = @organization.website_address_txt
      # Normalize website URL
      website = "https://#{website}" unless website.start_with?('http')
      prompt_parts << "Website: #{website}"
    end

    # Add contributing manager if available
    if @organization.contributing_manager_nm.present?
      prompt_parts << "Key Contact: #{@organization.contributing_manager_nm}"
    end

    # Add location if available
    if @organization.us_address.present?
      prompt_parts << "Address: #{@organization.us_address}"
    end

    prompt_parts << ""
    prompt_parts << "This is a private foundation that provides scholarships. Please search for:"
    prompt_parts << "1. Email for scholarship or grant inquiries"
    prompt_parts << "2. General contact email address"
    prompt_parts << "3. Email of the foundation director or contributing manager"
    prompt_parts << ""
    prompt_parts << "Instructions:"
    prompt_parts << "- You MUST perform a web search to find current information"
    prompt_parts << "- Look for contact pages, about pages, or application information"
    prompt_parts << "- If you find an email address, return ONLY that email address"
    prompt_parts << "- If you cannot find any email after searching, return exactly: not_found"

    prompt_text = prompt_parts.join("\n")

    puts "    [DEBUG] Making API call to #{model_name}..."
    Rails.logger.debug "EmailSearchService: Using model #{model_name}"
    Rails.logger.debug "EmailSearchService: Prompt: #{prompt_text}"

    # Use the new google_search tool (for Gemini 2.0+)
    request_body = {
      contents: [{
        parts: [{
          text: prompt_text
        }]
      }],
      tools: [{
        google_search: {}
      }]
    }

    Rails.logger.debug "EmailSearchService: Request body: #{request_body.to_json}"

    response = Faraday.post(endpoint, request_body.to_json, {
      'Content-Type' => 'application/json',
      'x-goog-api-key' => @api_key
    })

    puts "    [DEBUG] API returned status: #{response.status}"
    Rails.logger.debug "EmailSearchService: API response status: #{response.status}"

    raise AiSearchError, "Rate limit exceeded" if response.status == 429

    unless response.success?
      error_body = response.body[0..500] rescue "Unable to read body"
      puts "    [DEBUG] API error body: #{error_body}"
      raise AiSearchError, "API request failed: #{response.status} - #{error_body}"
    end

    result = JSON.parse(response.body)

    # Log the full response for debugging
    puts "    [DEBUG] API response keys: #{result.keys}"
    if result['candidates']
      puts "    [DEBUG] Candidates count: #{result['candidates'].length}"
      if result['candidates'][0]
        puts "    [DEBUG] First candidate keys: #{result['candidates'][0].keys}"
        if result['candidates'][0]['content']
          puts "    [DEBUG] Content parts: #{result['candidates'][0]['content']['parts']&.length || 0}"
        end
        # Check for groundingMetadata which indicates search was used
        if result['candidates'][0]['groundingMetadata']
          grounding = result['candidates'][0]['groundingMetadata']
          puts "    [DEBUG] ✓ Grounding metadata present - web search was used!"
          if grounding['webSearchQueries']
            puts "    [DEBUG] Search queries used: #{grounding['webSearchQueries'].join(', ')}"
          end
          if grounding['groundingChunks']
            puts "    [DEBUG] Sources found: #{grounding['groundingChunks'].length}"
          end
        else
          puts "    [DEBUG] ✗ No grounding metadata - web search may not have been used"
        end
      end
    end

    Rails.logger.debug "EmailSearchService: Full API response: #{result.to_json[0..1000]}"

    # Extract the text from the response
    email = result.dig("candidates", 0, "content", "parts", 0, "text")&.strip

    if email.blank?
      Rails.logger.warn "EmailSearchService: No text content in API response for #{@organization.name}"
      return nil
    end

    puts "    [DEBUG] Raw AI response: #{email[0..200]}"

    # Clean up the response - sometimes AI adds extra text
    email_cleaned = email.downcase.strip

    # If it says not found, return nil
    return nil if email_cleaned == 'not_found' || email_cleaned.include?('not found') || email_cleaned.include?('cannot find')

    # Try to extract just the email address if there's extra text
    email_match = email.match(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    if email_match
      found_email = email_match[0]
      Rails.logger.info "EmailSearchService: Found email #{found_email} for #{@organization.name}"
      return found_email
    end

    # If we couldn't extract a valid email, log and return nil
    Rails.logger.warn "EmailSearchService: Response didn't contain valid email for #{@organization.name}: #{email[0..100]}"
    nil
  end
end
