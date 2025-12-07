# lib/tasks/debug_grounding.rake
namespace :debug do
  desc "Run a step-by-step debug trace of the grounding task using Google Search. Prompts for question interactively."
  task :grounding_with_google => :environment do
    puts "---"
    puts "DEBUG TRACE: GROUNDING WITH GOOGLE SEARCH"
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
      puts "\n[STEP 1] Running RAG search to find and synthesize context..."
      rag_service = RagSearchService.new(question, search_provider_class: GoogleSearchService)
      context, sources, search_results = rag_service.search_and_synthesize
      puts "  -> Step 1 complete. Found context from #{sources.count} relevant sources."

      puts "\n[STEP 2] Displaying intermediate results..."
      puts "  --- TOP WEB SEARCH RESULTS ---"
      if search_results && search_results["results"]&.any?
        search_results["results"].first(3).each_with_index do |result, index|
          puts "    [#{index + 1}] #{result['title']}"
          puts "        URL: #{result['url']}"
        end
      else
        puts "    No web search results were returned."
      end
      puts "  ------------------------------"

      puts "\n  --- CONTEXT SENT TO LLM ---"
      puts context
      puts "  ---------------------------\n"

      puts "\n[STEP 3] Generating grounded response from LLM..."
      grounding_service = GroundingService.new
      grounded_response = grounding_service.answer_from_context(question, context)
      puts "  -> Step 3 complete."

      puts "\n[STEP 4] Displaying final answer..."
      puts "\n----------------------------------"
      puts "GROUNDED ANSWER"
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

    rescue RagSearchService::RagSearchError => e
      puts "\n--- ERROR ---"
      puts "The RAG search process failed: #{e.message}"
    rescue => e
      puts "\n--- UNEXPECTED ERROR ---"
      puts "An unexpected error occurred: #{e.class} - #{e.message}"
      puts e.backtrace.first(10).join("\n")
    end
    puts "----------------------------------"
    puts "DEBUG TRACE COMPLETE"
  end

  desc "Run a step-by-step debug trace of the grounding task using SearXNG. Prompts for question interactively."
  task :grounding_with_searxng => :environment do
    puts "---"
    puts "DEBUG TRACE: GROUNDING WITH SEARXNG"
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
      puts "\n[STEP 1] Running RAG search to find and synthesize context..."
      rag_service = RagSearchService.new(question, search_provider_class: WebSearchService)
      context, sources, search_results = rag_service.search_and_synthesize
      puts "  -> Step 1 complete. Found context from #{sources.count} relevant sources."

      puts "\n[STEP 2] Displaying intermediate results..."
      puts "  --- TOP WEB SEARCH RESULTS ---"
      if search_results && search_results["results"]&.any?
        search_results["results"].first(3).each_with_index do |result, index|
          puts "    [#{index + 1}] #{result['title']}"
          puts "        URL: #{result['url']}"
        end
      else
        puts "    No web search results were returned."
      end
      puts "  ------------------------------"

      puts "\n  --- CONTEXT SENT TO LLM ---"
      puts context
      puts "  ---------------------------\n"

      puts "\n[STEP 3] Generating grounded response from LLM..."
      grounding_service = GroundingService.new
      grounded_response = grounding_service.answer_from_context(question, context)
      puts "  -> Step 3 complete."

      puts "\n[STEP 4] Displaying final answer..."
      puts "\n----------------------------------"
      puts "GROUNDED ANSWER"
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

    rescue RagSearchService::RagSearchError => e
      puts "\n--- ERROR ---"
      puts "The RAG search process failed: #{e.message}"
    rescue => e
      puts "\n--- UNEXPECTED ERROR ---"
      puts "An unexpected error occurred: #{e.class} - #{e.message}"
      puts e.backtrace.first(10).join("\n")
    end
    puts "----------------------------------"
    puts "DEBUG TRACE COMPLETE"
  end
end
