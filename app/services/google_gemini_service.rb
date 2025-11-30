# app/services/google_gemini_service.rb
require "google_palm_api"

class GoogleGeminiService
  class Error < StandardError; end

  def initialize(api_key: Rails.application.credentials.google_palm_api_key)
    @api_key = api_key
    raise Error, "Google Palm API key not found" unless @api_key
  end

  def find_email_for_organization(organization_name, website)
    client = GooglePalmApi::Client.new(api_key: @api_key)
    prompt = <<~PROMPT
      Your task is to find the primary contact email address for a specific organization.
      Organization Name: "#{organization_name}"
      Website: #{website}

      Instructions:
      1. Search the organization's website and other reliable sources to find the best email address for general inquiries or contact.
      2. Return only the email address and nothing else.
      3. If you cannot find an email address, return the text "Not Found".
    PROMPT

    response = client.generate_text(
      model: "gemini-pro",
      prompt: { text: prompt }
    )

    if response.success? && response.data["candidates"].any?
      email = response.data["candidates"][0]["output"].strip
      return nil if email == "Not Found"
      email
    else
      nil
    end
  end
end
