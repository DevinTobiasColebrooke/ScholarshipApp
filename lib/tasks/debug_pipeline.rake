# lib/tasks/debug_pipeline.rake

# This file contains Rake tasks designed to test and debug
# specific steps of the RAG (Retrieval-Augmented Generation) pipeline.

namespace :debug do

  desc "PIPELINE STEP 2: Test fetching content from a single URL. Args: [url]"
  task :pipeline_step_2_fetch_content, [ :url ] => :environment do |_, args|
    url = args[:url]
    abort("Usage: rake 'debug:pipeline_step_2_fetch_content[http://example.com]'") if url.blank?

    puts "---"
    puts "DEBUG: PIPELINE STEP 2 - CONTENT FETCHING"
    puts "---"
    puts "Attempting to fetch content from:"
    puts "  URL: #{url}"

    browser = nil
    begin
      puts "\n[ACTION] Initializing headless browser and calling WebSearchService.fetch_page_content..."
      browser = Ferrum::Browser.new
      extracted_text = WebSearchService.fetch_page_content(url, browser: browser)
      puts "  -> Content extraction complete."

      puts "\n[RESULT] Extracted text:"
      puts "------------------------------------------------------------------"
      if extracted_text.present?
        puts extracted_text
      else
        puts "(No text was extracted from the page)"
      end
      puts "------------------------------------------------------------------"

    rescue => e
      puts "\n--- UNEXPECTED ERROR ---"
      puts "An unexpected error occurred: #{e.class} - #{e.message}"
      puts e.backtrace.first(10).join("\n")
    ensure
      if browser
        browser.quit
        puts "\nBrowser instance has been closed."
      end
    end
  end

  desc "PIPELINE STEP 3: Test the full RAG context synthesis. Args: [question]"
  task :pipeline_step_3_synthesize_context, [ :question ] => :environment do |_, args|
    question = args[:question]
    abort("Usage: rake 'debug:pipeline_step_3_synthesize_context[Your question here]'") if question.blank?

    puts "---"
    puts "DEBUG: PIPELINE STEP 3 - RAG CONTEXT SYNTHESIS"
    puts "---"
    puts "Original question: '#{question}'"
    
    begin
      puts "\n[ACTION] Running the full RagSearchService pipeline..."
      # Using SearXNG by default for this debug task
      rag_service = RagSearchService.new(question, search_provider_class: WebSearchService)
      context, sources, search_results = rag_service.search_and_synthesize
      puts "  -> RAG pipeline complete."
      
      puts "\n--- [RESULT 1] TOP SEARCH RESULTS ---"
      if search_results && search_results["results"]&.any?
        search_results["results"].first(5).each_with_index do |result, index|
          puts "  [#{index + 1}] #{result['title']}"
          puts "      URL: #{result['url']}"
        end
      else
        puts "  No web search results were returned."
      end
      
      puts "\n--- [RESULT 2] SOURCES USED FOR CONTEXT ---"
      if sources.any?
        sources.each_with_index do |source_url, index|
          puts "  [#{index + 1}] #{source_url}"
        end
      else
        puts "  No sources were used to build the context."
      end

      puts "\n--- [RESULT 3] FINAL SYNTHESIZED CONTEXT ---"
      puts " (This is the exact text that would be sent to the LLM for the final answer)"
      puts "------------------------------------------------------------------"
      puts context
      puts "------------------------------------------------------------------"

    rescue => e
      puts "\n--- UNEXPECTED ERROR ---"
      puts "An unexpected error occurred: #{e.class} - #{e.message}"
      puts e.backtrace.first(10).join("\n")
    end
  end

end
