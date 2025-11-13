# app/services/embedding_service.rb
require 'net/http'
require 'json'

class EmbeddingService
  class EmbeddingError < StandardError; end

  def self.call(text, task: 'search_query')
    new(text, task: task).call
  end

  def initialize(text, task: 'search_query')
    @text = text
    @task = task
    # IMPORTANT: Replace 'YOUR_WINDOWS_IP_ADDRESS' with the actual IP address of your Windows machine.
    @uri = URI('http://172.18.48.1:8080/embeddings')
  end

  def call
    http = Net::HTTP.new(@uri.host, @uri.port)
    request = Net::HTTP::Post.new(@uri.path, { 'Content-Type' => 'application/json' })

    # The model expects the text to be prefixed with the task type, unless it's already prefixed.
    prefixed_text = if @text.start_with?('search_document: ')
                      @text
                    else
                      "#{@task}: #{@text}"
                    end

    request.body = { content: prefixed_text }.to_json

    begin
      response = http.request(request)
      raise EmbeddingError, "HTTP Error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      body = JSON.parse(response.body)

      if body.is_a?(Array) && body.first.is_a?(Hash) && body.first.key?('embedding')
        embedding_data = body.first['embedding']
        if embedding_data.is_a?(Array)
          embedding_data.flatten.map(&:to_f)
        else
          raise EmbeddingError, "Invalid embedding data format"
        end
      else
        raise EmbeddingError, "Invalid response format"
      end
    rescue JSON::ParserError => e
      raise EmbeddingError, "JSON Parsing Error: #{e.message}"
    rescue StandardError => e
      raise EmbeddingError, "Embedding request failed: #{e.message}"
    end
  end
end
