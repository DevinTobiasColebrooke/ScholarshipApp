# lib/tasks/debug_combined_search.rake
require "parallel"

namespace :debug do
  # This is a helper module to encapsulate the RAG pipeline logic,
  # adapted from RagSearchService to work on a pre-defined list of URLs.
  module CombinedSearchHelper
    def run_rag_pipeline_on_urls(question:, urls:)
      # 1. Fetch, Chunk Content
      Rails.logger.info "RAG (Combined): Fetching and chunking content from #{urls.count} unique URLs..."
      all_chunks = fetch_and_chunk_content(urls)
      return nil if all_chunks.empty? # Return nil if no context can be built
      Rails.logger.info "RAG (Combined): Generated #{all_chunks.count} text chunks."

      # 2. Perform Vector Similarity Search
      Rails.logger.info "RAG (Combined): Embedding query and text chunks..."
      query_embedding = EmbeddingService.call(question, task: "search_query")
      chunks_with_embeddings = embed_chunks(all_chunks)
      embeddable_chunks = chunks_with_embeddings.reject { |c| c[:embedding].nil? }
      return nil if embeddable_chunks.empty?
      Rails.logger.info "RAG (Combined): Embeddings generated."

      Rails.logger.info "RAG (Combined): Performing semantic ranking..."
      top_chunks = find_top_chunks(query_embedding, embeddable_chunks)
      Rails.logger.info "RAG (Combined): Found top #{top_chunks.count} most relevant chunks."

      # 3. Assemble Dense Context
      Rails.logger.info "RAG (Combined): Assembling final context..."
      context = ""
      top_chunks.each do |top_chunk_data|
        chunk_data = embeddable_chunks[top_chunk_data[:index]]
        context += "Source URL: #{chunk_data[:source_url]}\nContent:\n#{chunk_data[:text]}\n\n---\n\n"
      end
      
      context
    end

    private

    def fetch_and_chunk_content(urls)
      all_chunks = []
      browser = Ferrum::Browser.new
      urls.each do |url|
        Rails.logger.debug "RAG: Processing #{url}"
        content = WebSearchService.fetch_page_content(url, browser: browser)
        if content.present?
          chunks = content.split(/\n\n+/).map(&:strip).reject(&:empty?)
          chunks.each do |chunk|
            all_chunks << { text: chunk, source_url: url }
          end
        end
      end
      all_chunks
    ensure
      browser&.quit
    end

    def embed_chunks(chunks)
      Parallel.map_with_index(chunks) do |chunk, index|
        begin
          embedding = EmbeddingService.call(chunk[:text], task: "search_document")
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
        { index: index, score: cosine_similarity(query_embedding, chunk[:embedding]) }
      end
      scored_chunks.sort_by { |c| -c[:score] }.first(7)
    end

    def dot_product(vec1, vec2); vec1.zip(vec2).map { |x, y| x * y }.sum; end
    def magnitude(vec); Math.sqrt(vec.map { |x| x**2 }.sum); end
    def cosine_similarity(vec1, vec2)
      mag1 = magnitude(vec1)
      mag2 = magnitude(vec2)
      return 0 if mag1 == 0 || mag2 == 0
      dot_product(vec1, vec2) / (mag1 * mag2)
    end
  end

  desc "Run grounding with a combined search from Google and SearXNG. Prompts for question interactively."
  task :grounding_with_combined_search => :environment do
    extend CombinedSearchHelper

    puts "---"
    puts "DEBUG TRACE: GROUNDING WITH COMBINED SEARCH (Google + SearXNG)"
    puts "---"
    
    print "Please enter your question: "
    question = STDIN.gets.chomp
    if question.blank?
      puts "No question entered. Exiting."
      next
    end

    puts "Original question: '#{question}'"
    puts "----------------------------------"

    begin
      # 1. Search both providers
      puts "\n[STEP 1] Searching with Google..."
      google_results = GoogleSearchService.search(question)
      google_urls = google_results&.dig("results")&.map { |r| r["url"] } || []
      puts "  -> Found #{google_urls.count} URLs from Google."

      puts "\n[STEP 2] Searching with SearXNG..."
      searxng_results = WebSearchService.search(question)
      searxng_urls = searxng_results&.dig("results")&.map { |r| r["url"] } || []
      puts "  -> Found #{searxng_urls.count} URLs from SearXNG."

      # 2. Combine and de-duplicate URLs
      combined_urls = (google_urls + searxng_urls).uniq
      puts "\n[STEP 3] Combined and de-duplicated search results."
      puts "  -> Total unique URLs to process: #{combined_urls.count}"

      # 3. Run the rest of the RAG pipeline on the combined URLs
      context = run_rag_pipeline_on_urls(question: question, urls: combined_urls)

      # 4. Generate grounded response from the "super-context"
      puts "\n[STEP 4] Generating final answer from combined context..."
      grounding_service = GroundingService.new
      grounded_response = grounding_service.answer_from_context(question, context)
      puts "  -> Final answer generated."

      # 5. Display result
      puts "\n----------------------------------"
      puts "GROUNDED ANSWER (from Combined Search)"
      puts "----------------------------------"
      puts "\nAnswer: #{grounded_response['answer']}"

      if grounded_response["citations"]&.any?
        puts "\nSources:"
        grounded_response["citations"].each_with_index do |citation, index|
          puts "  [#{index + 1}] #{citation['source_url']}"
          puts "      Quote: \"#{citation['text']}\""
        end
      else
        puts "\nNo citations were provided."
      end

    rescue => e
      puts "\n--- UNEXPECTED ERROR ---"
      puts "An unexpected error occurred: #{e.class} - #{e.message}"
      puts e.backtrace.first(10).join("\n")
    end
    puts "----------------------------------"
    puts "COMBINED SEARCH TRACE COMPLETE"
  end

  desc "Run a verbose debug trace of the combined search email discovery with full reprocessing. Args: [limit (default 10)]"
  task :combined_search_reprocess_test, [ :limit ] => :environment do |_, args|
    extend EmailOutreachHelpers
    extend CombinedSearchHelper

    limit = args[:limit]&.to_i || 10

    print_header("DEBUG TRACE: COMBINED SEARCH REPROCESS (LIMIT: #{limit})")
    
    puts "\n-- REPROCESS MODE ENABLED --"
    puts "Deleting all existing outreach contacts for '#{EmailOutreachHelpers::CAMPAIGN_NAME}' to start from the beginning..."
    deleted_count = OutreachContact.where(campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME).delete_all
    puts "  -> Deleted #{deleted_count} records."
    
    EmailSearchService.reset_daily_limit_flag
    
    organizations = target_organizations.order(:id).limit(limit).to_a
    
    if organizations.empty?
      abort("\nNo organizations found in the target scope to process.")
    end

    puts "\nProcessing #{organizations.count} organizations from the start of the scope..."
    puts "Starting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    
    email_service_instance = EmailSearchService.new(nil)

    organizations.each_with_index do |org, index|
      print_header("PROCESSING ORGANIZATION #{index + 1} / #{organizations.count}: #{org.name} (ID: #{org.id})")
      begin
        # 1. Build the search query by setting the organization on the instance first
        email_service_instance.instance_variable_set(:@organization, org)
        query = email_service_instance.send(:build_web_search_query)
        puts "\n[STEP 1] Built Search Query: '#{query}'"

        # 2. Search both providers
        puts "\n[STEP 2] Searching with Google..."
        google_urls = GoogleSearchService.search(query)&.dig("results")&.map { |r| r["url"] } || []
        puts "  -> Found #{google_urls.count} URLs from Google."

        puts "\n[STEP 3] Searching with SearXNG..."
        searxng_urls = WebSearchService.search(query)&.dig("results")&.map { |r| r["url"] } || []
        puts "  -> Found #{searxng_urls.count} URLs from SearXNG."
        
        # 3. Combine and de-duplicate URLs
        combined_urls = (google_urls + searxng_urls).uniq
        puts "\n[STEP 4] Combined and de-duplicated search results."
        puts "  -> Total unique URLs to process: #{combined_urls.count}"

        if combined_urls.empty?
          raise "No search results found from either Google or SearXNG."
        end

        # 4. Run the RAG pipeline
        context = run_rag_pipeline_on_urls(question: query, urls: combined_urls)

        # 5. Extract email from the "super-context"
        puts "\n[STEP 5] Generating final email extraction from combined context..."
        if context.present?
          email_service_instance.instance_variable_set(:@organization, org)
          email, raw_llm_response = email_service_instance.send(:extract_email_with_llm, context)
        else
          email = nil
          raw_llm_response = "No context was generated."
        end
        puts "  -> LLM call complete."

        # 6. Display results for this organization
        puts "\n--- RESULTS FOR #{org.name} ---"
        puts "[Context Sent to LLM]"
        puts context || "(No context generated)"
        puts "\n[Raw LLM Response]"
        puts raw_llm_response
        puts "\n[Final Extracted Result]"
        if email
          puts "  ✓ Success! Found email: #{email}"
        else
          puts "  ○ Email not found."
        end

        # 7. Save to DB
        update_outreach_contact(org: org, email: email)
        puts "\n[DB ACTION] Saved result to database."

      rescue => e
        puts "\n--- ERROR FOR #{org.name} ---"
        puts "An error occurred: #{e.class} - #{e.message}"
        puts "Backtrace:"
        puts e.backtrace.join("\n")
      end
    end

    print_header("DEBUG REPROCESS TEST COMPLETE")
  end
end