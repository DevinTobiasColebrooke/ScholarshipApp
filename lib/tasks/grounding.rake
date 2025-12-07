# lib/tasks/grounding.rake
namespace :grounding do
  desc "Provides instructions on how to test the web search grounding functionality."
  task :answer_question do
    puts "This task has been replaced by more specific debug tasks."
    puts "Please use one of the following tasks to test the grounding functionality:"
    puts "\n--------------------------------------------------------------------------"
    puts "To test with Google Custom Search:"
    puts "  rake 'debug:grounding_with_google[Your question here]'"
    puts "\nTo test with the local SearXNG instance:"
    puts "  rake 'debug:grounding_with_searxng[Your question here]'"
    puts "--------------------------------------------------------------------------"
  end
end
