# app/services/rag_search_service.rb

require 'parallel'

class RagSearchService
  class RagSearchError < StandardError; end

  def initialize(query, transform: true)
    @query = query
    @transform = transform
    @grounding_service = GroundingService.new
  end

  # Main method to orchestrate the entire RAG process
  def search_and_synthesize
    # 1. Transform Query (optional)
    search_query = if @transform
      @grounding_service.transform_query(@query)
    else
      @query
    end
    Rails.logger.info "RAG: Original Query: '#{@query}'"
    Rails.logger.info "RAG: Final Search Query: '#{search_query}' (Transform applied: #{@transform})"

    # 2. Search Web
    search_results = WebSearchService.search(search_query)
    unless search_results && search_results['results']&.any?
      raise RagSearchError, "Could not find any search results for the query."
    end
    
    top_urls = search_results['results'].first(10).map { |r| r['url'] }
    Rails.logger.info "RAG: Found top #{top_urls.count} URLs: #{top_urls.join(', ')}"

    # 3. Fetch, Chunk, and Embed Content
    all_chunks = fetch_and_chunk_content(top_urls)

    if all_chunks.empty?
      raise RagSearchError, "Could not fetch or chunk any content from the search result URLs."
    end

    # 4. Perform Vector Similarity Search
    # Always use the original query for the embedding to capture the user's semantic intent
    query_embedding = EmbeddingService.call(@query, task: 'search_query')
    chunks_with_embeddings = embed_chunks(all_chunks)
    
    embeddable_chunks = chunks_with_embeddings.reject { |c| c[:embedding].nil? }
    if embeddable_chunks.empty?
      raise RagSearchError, "Could not generate any embeddings for the text chunks."
    end

    top_chunks = find_top_chunks(query_embedding, embeddable_chunks)
    Rails.logger.info "RAG: Found top #{top_chunks.count} most relevant chunks."

    # 5. Assemble Dense Context
    context = ""
    source_urls = Set.new
    top_chunks.each do |top_chunk_data|
      chunk_data = embeddable_chunks[top_chunk_data[:index]]
      context += "Source URL: #{chunk_data[:source_url]}\nContent:\n#{chunk_data[:text]}\n\n---\n\n"
      source_urls.add(chunk_data[:source_url])
    end

    return [context, source_urls.to_a, search_results]
  end

  private

  def fetch_and_chunk_content(urls)
    all_chunks = []
    urls.each do |url|
      Rails.logger.debug "RAG: Processing #{url}"
      content = WebSearchService.fetch_page_content(url)
      if content.present?
        chunks = content.split(/\n\n+/).map(&:strip).reject(&:empty?)
        chunks.each do |chunk|
          all_chunks << { text: chunk, source_url: url }
        end
      end
    end
    Rails.logger.info "RAG: Generated #{all_chunks.count} text chunks from #{urls.count} URLs."
    all_chunks
  end

  def embed_chunks(chunks)
    Rails.logger.info "RAG: Generating embeddings for #{chunks.count} text chunks (in parallel)..."
    Parallel.map_with_index(chunks) do |chunk, index|
      begin
        embedding = EmbeddingService.call(chunk[:text], task: 'search_document')
        Rails.logger.debug "RAG: Embedded chunk #{index + 1}/#{chunks.count}"
        chunk.merge(embedding: embedding)
      rescue EmbeddingService::EmbeddingError => e
        Rails.logger.warn "RAG: Could not embed chunk #{index + 1}: #{e.message}"
        chunk.merge(embedding: nil)
      end
    end
  end

  def find_top_chunks(query_embedding, embeddable_chunks)
    chunk_embeddings = embeddable_chunks.map { |c| c[:embedding] }

    scored_chunks = embeddable_chunks.map.with_index do |chunk, index|
      {
        index: index,
        score: cosine_similarity(query_embedding, chunk[:embedding])
      }
    end

    scored_chunks.sort_by { |c| -c[:score] }.first(7)
  end

  # -- Manual Cosine Similarity Calculation --
  def dot_product(vec1, vec2)
    vec1.zip(vec2).map { |x, y| x * y }.sum
  end

  def magnitude(vec)
    Math.sqrt(vec.map { |x| x**2 }.sum)
  end

  def cosine_similarity(vec1, vec2)
    # Ensure vectors are not zero to avoid division by zero
    mag1 = magnitude(vec1)
    mag2 = magnitude(vec2)
    return 0 if mag1 == 0 || mag2 == 0
    dot_product(vec1, vec2) / (mag1 * mag2)
  end
end
