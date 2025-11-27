namespace :web_search do
  desc "Test the full web search, fetch, and embedding pipeline with a real query"
  task :test, [:query] => :environment do |_, args|
    if args[:query].blank?
      puts "Usage: rails web_search:test[search query]"
      next
    end

    puts "Starting web search test with query: '#{args[:query]}'"

    # 1. Search the web using the instance's default engines
    puts "Step 1: Searching the web..."
    search_results = WebSearchService.search(args[:query])

    unless search_results && search_results["results"]&.any?
      puts "Search returned no results or an error occurred."
      next
    end

    puts "  - Top 3 search results:"
    search_results["results"].first(3).each_with_index do |result, index|
      puts "    #{index + 1}. Title: #{result['title']}"
      puts "       URL: #{result['url']}"
      puts "       Snippet: #{result['content']&.truncate(100)}"
    end

    first_url = search_results["results"].first["url"]
    puts "  - Proceeding with first URL: #{first_url}"

    # 2. Fetch the page content
    puts "Step 2: Fetching page content..."
    fetched_content = WebSearchService.fetch_page_content(first_url)

    if fetched_content.blank?
      puts "Failed to fetch content from the URL."
      next
    end

    puts "  - Fetched content (first 100 chars): #{fetched_content.truncate(100)}"

    # 3. Generate embedding
    puts "Step 3: Generating embedding for the content..."
    begin
      truncated_content = fetched_content.truncate(8000)
      embedding_vector = EmbeddingService.call(truncated_content, task: 'search_document')
      puts "  - Embedding generated successfully."
    rescue EmbeddingService::EmbeddingError => e
      puts "Error generating embedding: #{e.message}"
      next
    end

    # 4. Store the WebDocument
    puts "Step 4: Storing the WebDocument..."
    web_document = WebDocument.create(
      url: first_url,
      content: fetched_content,
      embedding: embedding_vector
    )

    if web_document.persisted?
      puts "Successfully created WebDocument with id: #{web_document.id}"
    else
      puts "Failed to create WebDocument: #{web_document.errors.full_messages.to_sentence}"
    end

    puts "Web search test finished."
  end
end
