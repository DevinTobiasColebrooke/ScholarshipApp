require "net/http"
require "uri"
require "json"

class KnowledgeBaseService
  # Configuration for the Embedding Model Server
  # TODO: Move these configurations to Rails credentials or a dedicated initializer.
  EMBEDDING_SERVER_URL = URI("http://10.0.0.202:8081/embedding").freeze
  EMBEDDING_DIMENSION = 768 # Confirmed by user's existing schema
  MAX_CHARS_FOR_EMBEDDING = 2000 # Matches original script's truncation limit

  def self.get_embedding(text)
    http = Net::HTTP.new(EMBEDDING_SERVER_URL.host, EMBEDDING_SERVER_URL.port)
    request = Net::HTTP::Post.new(EMBEDDING_SERVER_URL)
    request["Content-Type"] = "application/json"
    request.body = { input: text }.to_json

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error "KnowledgeBaseService: Embedding server error: #{response.code} - Body: #{response.body}"
      return nil
    end

    parsed_response = JSON.parse(response.body)

    # The llama-server returns an array of objects. We need to get the first one.
    if parsed_response.is_a?(Array) && !parsed_response.empty?
      first_result = parsed_response.first
      if first_result.is_a?(Hash) && first_result["embedding"]
        # The server returns a nested array for the embedding, e.g., [[0.1, 0.2, ...]]
        # pgvector expects a flat array, so we take the first element.
        return first_result["embedding"].first
      end
    end

    Rails.logger.error "KnowledgeBaseService: Embedding server returned an unexpected response format. Body: #{response.body}"
    nil
  rescue => e
    Rails.logger.error "KnowledgeBaseService: Error getting embedding: #{e.message}"
    nil
  end

  def self.store_document(url, content, summary: nil)
    # Truncate content for the embedding model if it's too large.
    # The full content is still stored in the database.
    # We'll use a constant for this, similar to MAX_WEBPAGE_CONTENT_CHARS in the original script.
    truncated_content_for_embedding = content.slice(0, MAX_CHARS_FOR_EMBEDDING)

    embedding = get_embedding(truncated_content_for_embedding)

    unless embedding
      Rails.logger.warn "KnowledgeBaseService: Failed to get embedding for document from #{url}. Skipping storage."
      return nil
    end

    web_document = WebDocument.find_or_initialize_by(url: url)
    web_document.content = content
    web_document.summary = summary
    web_document.embedding = embedding

    if web_document.save
      Rails.logger.info "KnowledgeBaseService: Successfully stored/updated #{url} in web_documents."
      web_document
    else
      Rails.logger.error "KnowledgeBaseService: Failed to save web document for #{url}: #{web_document.errors.full_messages.to_sentence}"
      nil
    end
  rescue => e
    Rails.logger.error "KnowledgeBaseService: An unexpected error occurred during document storage for #{url}: #{e.message}"
    nil
  end
end
