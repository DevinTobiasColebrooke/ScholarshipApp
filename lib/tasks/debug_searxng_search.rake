# lib/tasks/debug_searxng_search.rake
require_relative "email_outreach/helpers"

namespace :debug do
  desc "Run a detailed, step-by-step debug trace of the email search task using SearXNG for a single organization"
  task :find_emails_with_searxng => :environment do
    provider = :searxng

    # 1. Setup Verbose Logging
    extend EmailOutreachHelpers
    setup_verbose_logger
    print_header("DEBUG TRACE FOR: Email Search with SearXNG")
    puts "Logger set to DEBUG level."
    puts "Using search provider: #{provider}"
    puts "---"

    # 2. Select Test Organization
    puts "\n[STEP 1] Selecting a test organization..."
    org = Organization.profile_white_woman_26.where.not(name: [ nil, "" ]).first

    unless org
      abort("ERROR: Could not find a suitable test organization.")
    end

    puts "  - ID:      #{org.id}"
    puts "  - Name:    #{org.name}"
    puts "  - EIN:     #{org.ein}"
    puts "  - Address: #{org.us_address}"
    puts "---"

    # 3. Initialize and Run the Service
    puts "\n[STEP 2] Initializing EmailSearchService..."
    puts "         This will trigger the full RAG pipeline: Search -> Fetch -> Chunk -> Embed -> Synthesize -> Extract"
    begin
      service = EmailSearchService.new(org, search_provider: provider)

      puts "\n[STEP 3] Calling `find_email_with_details`..."
      details = service.find_email_with_details

      puts "\n[STEP 4] Service call complete. Displaying detailed results..."
      puts "---\n"

      # 4. Display Detailed Debugging Information
      print_header("DETAILED RESULTS (SearXNG)")

      puts "[Web Search Query Used]"
      puts "  #{details[:web_search_query] || 'Not available'}"
      puts "-" * 20

      puts "\n[Context Sent to LLM for Extraction]"
      puts "  (This is the synthesized content from the most relevant parts of the fetched websites)"
      puts "---"
      puts details[:context] || "No context was generated."
      puts "---\n"

      puts "[Raw LLM Response for Email Extraction]"
      puts "---"
      puts details[:llm_response] || "No response from LLM."
      puts "---\n"

      # 5. Display Final Result
      print_header("FINAL EXTRACTED RESULT")
      found_email = details[:email]
      if found_email
        puts "  ✓ Success! Found email: #{found_email}"
      else
        puts "  ○ Email not found based on the provided context."
      end

    rescue => e
      print_header("AN ERROR OCCURRED DURING THE PROCESS")
      puts "  Class:   #{e.class}"
      puts "  Message: #{e.message}"
      puts "  Backtrace:"
      puts e.backtrace.first(10).map { |line| "    #{line}" }.join("\n")
    end

    print_header("DEBUG TRACE COMPLETE")
  end
end
