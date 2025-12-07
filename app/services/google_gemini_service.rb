# app/services/google_gemini_service.rb
require "faraday"
require "json"

class GoogleGeminiService
  class Error < StandardError; end

  BASE_URL_TEMPLATE = "https://generativelanguage.googleapis.com/v1beta/models/%<model>s:generateContent".freeze

  def initialize(api_key: Rails.application.credentials.google_gemini_key, model: "gemini-pro")
    @api_key = api_key
    @model = model
    raise Error, "Google Gemini API key not found" unless @api_key
  end

  def find_email_for_organization(organization_name, ein, us_address, manager_name)
    prompt = if manager_name.present?
      <<~PROMPT
        Your primary task is to find the direct email address for a specific person: '#{manager_name}', who is the contributing manager at the organization '#{organization_name}'.

        Organization Details:
        - Name: "#{organization_name}"
        - EIN: #{ein || 'Not provided'}
        - Address: #{us_address || 'Not provided'}

        Instructions:
        1. Search for the email address of '#{manager_name}'.
        2. If you cannot find a direct email for '#{manager_name}', then find the best general contact email address for the organization.
        3. Return only the single best email address you find.
        4. If you cannot find any email address at all, return the text "Not Found".
        5. CRITICAL: Do not include any other text or explanation. Just the email address or "Not Found".
      PROMPT
    else
      <<~PROMPT
        Your task is to find the primary contact email address for a specific organization.

        Organization Details:
        - Name: "#{organization_name}"
        - EIN: #{ein || 'Not provided'}
        - Address: #{us_address || 'Not provided'}

        Instructions:
        1. Search using the provided organization details to find the best email address for general inquiries or contact.
        2. Return only the email address you find.
        3. If you cannot find an email address, return the text "Not Found".
        5. CRITICAL: Do not include any other text or explanation. Just the email address or "Not Found".
      PROMPT
    end

    headers = { "Content-Type" => "application/json" }
    body = {
      "contents" => [ { "parts" => [ { "text" => prompt } ] } ],
      "tools" => [ { "google_search": {} } ]
    }

    base_url = format(BASE_URL_TEMPLATE, model: @model)
    response = Faraday.post(base_url, body.to_json, headers) do |req|
      req.params["key"] = @api_key
    end

    return [ nil, nil ] unless response.success?

    response_body = JSON.parse(response.body)
    raw_response = response_body.dig("candidates", 0, "content", "parts", 0, "text")&.strip

    if raw_response.blank? || raw_response.casecmp("Not Found").zero?
      return [ nil, raw_response ]
    end

    # The model sometimes returns conversational text. Extract the first valid email.
    email_match = raw_response.match(URI::MailTo::EMAIL_REGEXP)

    if email_match
      [ email_match[0], raw_response ]
    else
      Rails.logger.warn("GoogleGeminiService: Found non-email response for #{organization_name}: '#{raw_response}'")
      [ nil, raw_response ]
    end

  rescue Faraday::Error => e
    Rails.logger.error("GoogleGeminiService Faraday Error: #{e.message}")
    [ nil, nil ]
  rescue JSON::ParserError => e
    Rails.logger.error("GoogleGeminiService JSON Parser Error: #{e.message}")
    [ nil, nil ]
  end
end
