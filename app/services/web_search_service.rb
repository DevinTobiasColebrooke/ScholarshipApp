require "ferrum"
require "nokogiri"
require 'net/http'
require 'json'
require 'uri'

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
  def self.search(query, engines: 'google,bing', categories: 'general')
    uri = URI(SEARX_INSTANCE_URL)
    uri.path = '/search'
    params = {
      'q' => query,
      'format' => 'json',
      'engines' => engines,
      'categories' => categories
    }
    uri.query = URI.encode_www_form(params)

    begin
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'
        request['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.36'
        request['Accept-Language'] = 'en-US,en;q=0.9'
        request['Connection'] = 'keep-alive'
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

  def self.fetch_page_content(url)
    browser = Ferrum::Browser.new
    browser.go_to(url)
    html = browser.body
    browser.quit

    # Parse the HTML and extract the text from the body
    doc = Nokogiri::HTML(html)
    
    # Remove script and style elements
    doc.search('script', 'style').remove
    
    # Get the text, then clean up excessive blank lines
    text = doc.at('body')&.text.to_s
    text.gsub!(/(\n\s*){3,}/, "\n\n")
    
    text
  rescue Ferrum::Error => e
    Rails.logger.error "WebSearchService: Ferrum error fetching #{url}: #{e.message}"
    nil
  end
end
