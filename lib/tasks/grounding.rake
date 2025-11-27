# lib/tasks/grounding.rake
namespace :grounding do
  desc "Answer a question using web search grounding"
  task :answer_question, [:question] => :environment do |_, args|
    question = ENV['QUESTION'] || args[:question]
    if question.blank?
      puts "Usage: rails grounding:answer_question['Your question here']"
      puts "  OR: QUESTION='Your question here' rails grounding:answer_question"
      next
    end

    puts "Original question: '#{question}'"
    puts "----------------------------------"

    begin
      # 1. & 2. Use the new RAG Service to get dense context
      puts "Step 1: Running advanced RAG search to find and synthesize context..."
      rag_service = RagSearchService.new(question)
      context, sources, search_results = rag_service.search_and_synthesize
      puts "Step 1 complete. Found context from #{sources.count} relevant sources."

      puts "\n----------------------------------"
      puts "WEB SEARCH RESULTS"
      puts "----------------------------------"
      if search_results && search_results["results"]&.any?
        search_results["results"].each_with_index do |result, index|
          puts "  [#{index + 1}] #{result['title']}"
          puts "      URL: #{result['url']}"
          puts "      Content: #{result['content']&.truncate(200)}"
        end
      else
        puts "No web search results were returned."
      end

      # 3. Generate grounded response from LLM
      puts "\nStep 2: Generating grounded response from LLM..."
      grounding_service = GroundingService.new
      grounded_response = grounding_service.answer_from_context(question, context)

      # 4. Display result
      puts "\n----------------------------------"
      puts "GROUNDED ANSWER"
    rescue RagSearchService::RagSearchError => e
      puts "\n--- ERROR ---"
      puts "The RAG search process failed: #{e.message}"
    rescue => e
      puts "\n--- UNEXPECTED ERROR ---"
      puts "An unexpected error occurred: #{e.class} - #{e.message}"
      puts e.backtrace.join("\n")
    end
    puts "----------------------------------"
    puts "\nAnswer: #{grounded_response['answer']}"
    
    if grounded_response['citations']&.any?
      puts "\nSources:"
      grounded_response['citations'].each_with_index do |citation, index|
        puts "  [#{index + 1}] #{citation['source_url']}"
        puts "      Quote: \"#{citation['text']}\""
      end
    else
      puts "\nNo citations were provided."
    end
    
    if grounded_response['raw_response']
      puts "\n---RAW LLM RESPONSE---"
      puts grounded_response['raw_response']
    end
  end
end
