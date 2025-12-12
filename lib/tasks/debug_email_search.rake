# lib/tasks/debug_email_search.rake
require_relative "email_outreach/helpers"

namespace :debug do
  desc "Run a detailed, step-by-step debug trace of the `email_outreach:find_emails_with_google['free']` task for a single organization"
  task :find_emails_with_google => :environment do
    provider = :google

    # 1. Setup Verbose Logging
    extend EmailOutreachHelpers
    setup_verbose_logger
    print_header("DEBUG TRACE FOR: find_emails_with_google['free']")
    puts "Logger set to DEBUG level."
    puts "Using search provider: #{provider}"
    puts "---"

    # 2. Select Test Organization
    puts "\n[STEP 1] Selecting a test organization..."
    # Using a known organization from the user's previous output for consistency.
    org = Organization.find_by(name: "G RUSSELL MORGAN SCHOLARSHIP FUND 2284200")
    unless org
      # Fallback if the specific org isn't found
      org = Organization.profile_white_woman_26.where.not(name: [ nil, "" ]).first
    end

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
      # This is where the magic happens. All debug logs from the services will be printed here.
      details = service.find_email_with_details

      puts "\n[STEP 4] Service call complete. Displaying detailed results..."
      puts "---\n"

      # 4. Display Detailed Debugging Information
      print_header("DETAILED RESULTS")

      puts "[Web Search Query Used]"
      puts "  #{details[:web_search_query] || 'Not available'}"
      puts "-" * 20

      # NOTE: The RagSearchService logs the URLs it finds during its execution,
      # which will appear in the console output above this section.

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
