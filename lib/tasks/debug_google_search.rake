# lib/tasks/debug_google_search.rake
require_relative "../../app/services/google_search_service"
require_relative "email_outreach/helpers" # For print_header and setup_verbose_logger

namespace :debug do
  desc "Perform a direct search using GoogleSearchService and print raw results. Args: [query]"
  task :google_search, [ :query ] => :environment do |_, args|
    query = args[:query]
    unless query.present?
      puts "Usage: rake 'debug:google_search[your search query]'"
      abort("ERROR: A search query must be provided.")
    end

    extend EmailOutreachHelpers
    setup_verbose_logger # To see any debug logs from GoogleSearchService
    print_header("DIRECT GOOGLE SEARCH DEBUG")
    puts "Searching for: '#{query}'"
    puts "---"

    begin
      search_results = GoogleSearchService.search(query)

      print_header("RAW GOOGLE SEARCH RESULTS")
      if search_results && search_results["results"].any?
        puts "Found #{search_results["results"].count} results."
        search_results["results"].each_with_index do |result, index|
          puts "
[#{index + 1}]"
          puts "  Title: #{result['title']}"
          puts "  URL:   #{result['url']}"
          puts "  Snippet: #{result['content']}"
        end
      else
        puts "No results found for the query."
      end
    rescue GoogleSearchService::Error => e
      print_header("GOOGLE SEARCH SERVICE ERROR")
      puts "  Class:   #{e.class}"
      puts "  Message: #{e.message}"
    rescue => e
      print_header("UNEXPECTED ERROR")
      puts "  Class:   #{e.class}"
      puts "  Message: #{e.message}"
      puts "  Backtrace:"
      puts e.backtrace.first(5).map { |line| "    #{line}" }.join("\n")
    end

    print_header("DIRECT GOOGLE SEARCH COMPLETE")
  end
end
