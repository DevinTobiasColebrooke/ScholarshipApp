# frozen_string_literal: true

require 'faraday'
require 'json'
require 'thread'

class EmailSearchService
  class AiSearchError < StandardError; end

  # --- Model and Rate Limiting Configuration ---
  MODELS = [
    { name: 'gemini-pro', tool: :google_search_retrieval },
    { name: 'gemini-1.5-flash', tool: :google_search }
  ].freeze

  REQUEST_INTERVAL = 1.1 # seconds, for 60 QPM limit

  @@current_model_index = 0
  @@last_request_time = Time.at(0)
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

  def self.rate_limit
    @@mutex.synchronize do
      time_since_last_request = Time.now - @@last_request_time
      if time_since_last_request < REQUEST_INTERVAL
        sleep(REQUEST_INTERVAL - time_since_last_request)
      end
      @@last_request_time = Time.now
    end
  end
  # --- End Configuration ---

  def initialize(organization)
    @organization = organization
    @api_key = ENV['GEMINI_API_KEY']
  end

  def find_email
    self.class.rate_limit
    raise "GEMINI_API_KEY not set" if @api_key.blank?

    attempts = 0
    begin
      attempts += 1
      search_with_ai
    rescue AiSearchError => e
      if e.message.include?("Rate limit") && attempts < MODELS.length
        self.class.switch_model
        self.class.rate_limit # also wait before retrying
        retry
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
    tool_name = model_config[:tool]

    endpoint = "https://generativelanguage.googleapis.com/v1beta/models/#{model_name}:generateContent"
    
    prompt_text = "What is the contact email for the tax-exempt organization named '#{@organization.name}'?"
    if @organization.respond_to?(:contributing_manager_nm) && @organization.contributing_manager_nm.present?
      prompt_text += " The contributing manager is listed as '#{@organization.contributing_manager_nm}'."
    end
    prompt_text += " I am looking for the email of the contributing manager or a general contact email for the organization. Please only return the email address and nothing else. If you cannot find an email address, return 'not_found'."
    
    prompt = prompt_text

    response = Faraday.post(endpoint, {
      contents: [{
        parts: [{
          text: prompt
        }]
      }],
      tools: [{
        tool_name => {}
      }]
    }.to_json, {
      'Content-Type' => 'application/json',
      'x-goog-api-key' => @api_key
    })

    raise AiSearchError, "Rate limit exceeded" if response.status == 429
    raise AiSearchError, "API request failed: #{response.status}" unless response.success?

    result = JSON.parse(response.body)
    email = result.dig("candidates", 0, "content", "parts", 0, "text")&.strip

    return nil if email.blank? || email.downcase == 'not_found'

    email
  end
end
