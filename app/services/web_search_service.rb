require "ferrum"
require "nokogiri"
require "net/http"
require "json"
require "uri"

class WebSearchService
  # The base URL of the SearXNG instance.
  # You can host your own or find a public one.
  # A list of public instances can be found at https://searx.space/
  SEARX_INSTANCE_URL = "http://localhost:8888".freeze

  # Performs a search against the SearXNG API.
  #
  # @param query [String] The search query.
  # @param engines [String] Comma-separated list of engines to use.
  # @param categories [String] Comma-separated list of categories.
  # @return [Hash, nil] The parsed JSON response, or nil on error.
  def self.search(query, engines: nil, categories: "general")
    uri = URI(SEARX_INSTANCE_URL)
    uri.path = "/search"
    params = {
      "q" => query,
      "format" => "json",
      "categories" => categories,
      "language" => "en"
    }
    params["engines"] = engines if engines.present?

    begin
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Post.new(uri.path)
        request.set_form_data(params) # Send parameters as form data

        # Add headers similar to the GET request for consistency
        request["Accept"] = "application/json"
        request["User-Agent"] = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36"

        http.request(request)
      end

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        Rails.logger.error "WebSearchService: Error fetching search results: #{response.code} #{response.message}"
        Rails.logger.error "WebSearchService: Raw response body: #{response.body}" # Added for detailed debugging
        nil
      end
    rescue StandardError => e
      Rails.logger.error "WebSearchService: An error occurred during search: #{e.message}"
      nil
    end
  end

  def self.fetch_page_content(url, browser:)
    browser.go_to(url)
    browser.network.wait_for_idle

    html = browser.body

    # Attempt 1: Use Readability to find the main article content.
    clean_html = Readability::Document.new(html).content
    doc = Nokogiri::HTML(clean_html)
    text = doc.text.to_s.gsub(/(\n\s*){3,}/, "\n\n").strip

    # Attempt 2 (Fallback): If Readability produced very little text (e.g., on non-article pages),
    # fall back to extracting all text from the body.
    if text.length < 250
      Rails.logger.debug "WebSearchService: Readability content was too short. Falling back to full body text extraction for #{url}"
      doc = Nokogiri::HTML(html)
      # Remove script and style tags to avoid including code in the text
      doc.search('script', 'style').remove
      text = doc.text.to_s.gsub(/(\n\s*){3,}/, "\n\n").strip
    end
    
    text
  rescue Ferrum::Error => e
    Rails.logger.error "WebSearchService: Ferrum error fetching #{url}: #{e.message}"
    nil
  end
end