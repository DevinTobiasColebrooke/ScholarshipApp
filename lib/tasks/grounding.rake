# lib/tasks/grounding.rake
namespace :grounding do
  desc "Answer a question using web search grounding"
  task :answer_question, [:question] => :environment do |_, args|
    question = args[:question]
    if question.blank?
      puts "Usage: rails grounding:answer_question['Your question here']"
      next
    end

    puts "Answering question: '#{question}'"
    puts "----------------------------------"

    # 1. Search
    puts "Step 1: Searching the web..."
    search_results = WebSearchService.search(question)
    
    unless search_results && search_results['results']&.any?
      puts "Could not find any search results for the question."
      next
    end

    top_urls = search_results['results'].first(3).map { |r| r['url'] }
    puts "Found top URLs: #{top_urls.join(', ')}"

    # 2. Fetch and build context
    puts "\nStep 2: Fetching content and building context..."
    context = ""
    top_urls.each do |url|
      puts "  - Fetching from #{url}"
      content = WebSearchService.fetch_page_content(url)
      if content.present?
        # Truncate content to avoid overwhelming the LLM
        truncated_content = content.truncate(8000)
        context += "Source URL: #{url}\nContent:\n#{truncated_content}\n\n---\n\n"
      else
        puts "    (No content found)"
      end
    end

    if context.blank?
      puts "Could not fetch any content from the search result URLs."
      next
    end

    # 3. Generate grounded response from LLM
    puts "\nStep 3: Generating grounded response from LLM..."
    grounding_service = GroundingService.new
    grounded_response = grounding_service.answer_from_context(question, context)

    # 4. Display result
    puts "\n----------------------------------"
    puts "GROUNDED ANSWER"
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
