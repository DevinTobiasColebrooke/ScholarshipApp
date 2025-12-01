# app/services/google_gemini_service.rb
require "faraday"
require "json"

class GoogleGeminiService
  class Error < StandardError; end

  BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent".freeze

  def initialize(api_key: Rails.application.credentials.google_gemini_key)
    @api_key = api_key
    raise Error, "Google Gemini API key not found" unless @api_key
  end

  def find_email_for_organization(organization_name, website)
    prompt = <<~PROMPT
      Your task is to find the primary contact email address for a specific organization.
      Organization Name: "#{organization_name}"
      Website: #{website}

      Instructions:
      1. Search the organization's website and other reliable sources to find the best email address for general inquiries or contact.
      2. Return only the email address and nothing else.
      3. If you cannot find an email address, return the text "Not Found".
    PROMPT

    headers = { "Content-Type" => "application/json" }
    body = { "contents" => [{ "parts" => [{ "text" => prompt }] }] }

    response = Faraday.post(BASE_URL, body.to_json, headers) do |req|
      req.params["key"] = @api_key
    end

    return nil unless response.success?

    response_body = JSON.parse(response.body)
    
    # Correctly extract the text from the nested response structure
    if response_body.dig("candidates", 0, "content", "parts", 0, "text")
      email = response_body["candidates"][0]["content"]["parts"][0]["text"].strip
      return nil if email.blank? || email.casecmp("Not Found").zero?
      email
    else
      nil
    end

  rescue Faraday::Error => e
    Rails.logger.error("GoogleGeminiService Faraday Error: #{e.message}")
    nil
  rescue JSON::ParserError => e
    Rails.logger.error("GoogleGeminiService JSON Parser Error: #{e.message}")
    nil
  end
end
