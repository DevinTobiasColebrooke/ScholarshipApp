# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

class GoogleSearchService
  BASE_URL = "https://www.googleapis.com/customsearch/v1"

  class Error < StandardError; end
  class ApiError < Error; end

  # Performs a search using the Google Custom Search JSON API.
  #
  # @param query [String] The search query.
  # @return [Hash] A hash containing a 'results' key with a list of search result items.
  def self.search(query)
    api_key = Rails.application.credentials.google[:custom_search_api_key]
    search_engine_id = Rails.application.credentials.google[:custom_search_engine_id]

    if api_key.blank? || search_engine_id.blank?
      raise Error, "Google Custom Search API key or Search Engine ID is not configured."
    end

    uri = build_uri(query, api_key, search_engine_id)
    response = make_request(uri)
    handle_response(response)
  end

  private

  def self.build_uri(query, api_key, search_engine_id)
    params = {
      key: api_key,
      cx: search_engine_id,
      q: query,
      fields: "items(title,link,snippet)"
    }
    URI.parse("#{BASE_URL}?#{URI.encode_www_form(params)}")
  end

  def self.make_request(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Get.new(uri.request_uri)
    http.request(request)
  end

  def self.handle_response(response)
    case response
    when Net::HTTPSuccess
      json_response = JSON.parse(response.body)
      items = json_response["items"] || []
      # Normalize the output to match WebSearchService's expected format for RagSearchService
      formatted_results = items.map do |item|
        {
          "url" => item["link"],
          "title" => item["title"],
          "content" => item["snippet"]
        }
      end
      { "results" => formatted_results }
    else
      error_body = JSON.parse(response.body) rescue {}
      error_message = error_body.dig("error", "message") || "Unknown API error"
      raise ApiError, "API request failed with status #{response.code}: #{error_message}"
    end
  end
end
