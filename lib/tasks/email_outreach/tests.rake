require_relative "helpers"

namespace :email_outreach do
  extend EmailOutreachHelpers

  desc "Test email search with a single organization"
  task test_search: :environment do
    setup_verbose_logger
    print_header("TESTING EMAIL SEARCH SERVICE")
    EmailSearchService.reset_daily_limit_flag

    org = target_organizations.first
    abort("ERROR: No organizations found matching the profile.") unless org

    puts "\nTest Organization: #{org.name} (EIN: #{org.ein})"
    puts "  Website: #{org.website_address_txt || 'Not in database - AI will search'}"
    puts "  Contributing Manager: #{org.contributing_manager_nm}" if org.contributing_manager_nm.present?

    begin
      email, elapsed = find_email_for_org(org)

      print_header(email ? "SUCCESS! Email found in #{elapsed}s" : "NO EMAIL FOUND (in #{elapsed}s)")
      puts "Email: #{email}" if email
      puts "\nThe service is working correctly!"
      puts "Current Model: #{EmailSearchService.current_model[:name]}"
    rescue EmailSearchService::DailyLimitReached => e
      handle_service_unavailable(e)
    rescue => e
      handle_generic_error(e)
    end
  end

  desc "Test connection to local LLM server and model availability"
  task test_llm_connection: :environment do
    print_header("TESTING LOCAL LLM SERVER CONNECTION")
    # We need to require the service to access its constants
    require_relative("../../app/services/email_search_service")
    service = EmailSearchService

    puts "Attempting to connect to LLM server at: #{service::LLM_BASE_URL}"
    puts "Expected model name: #{service::LLM_MODEL_NAME}"

    begin
      llm_client = OpenAI::Client.new(access_token: service::LLM_API_KEY, uri_base: service::LLM_BASE_URL)
      puts "\nAttempting a simple chat completion request..."
      response = llm_client.chat(
        parameters: { model: service::LLM_MODEL_NAME, messages: [ { role: "user", content: "Hello" } ], max_tokens: 10 }
      )

      if (content = response.dig("choices", 0, "message", "content")&.strip).present?
        puts "\n✓ SUCCESS: Successfully connected and received a response."
        puts "LLM responded: \"#{content}\""
      else
        puts "\n✗ FAILURE: Connected, but received an unexpected or empty response."
        puts "Full response: #{response.inspect}"
      end
    rescue Faraday::ConnectionFailed => e
      puts "\n✗ FAILURE: Could not connect to LLM server at #{service::LLM_BASE_URL}."
      puts "Error: #{e.message}"
    rescue Faraday::ClientError => e
      puts "\n✗ FAILURE: LLM server returned an error (HTTP #{e.response[:status]})."
      puts "This often means the model '#{service::LLM_MODEL_NAME}' is not loaded on the server."
    rescue => e
      handle_generic_error(e)
    end
  end

  desc "Test email search with multiple organizations to see success rate"
  task :test_multiple, [ :count ] => :environment do |_task, args|
    count = args[:count]&.to_i || 5
    print_header("TESTING EMAIL SEARCH WITH #{count} ORGANIZATIONS")
    EmailSearchService.reset_daily_limit_flag

    orgs = target_organizations.limit(count).to_a
    abort("ERROR: No organizations found.") if orgs.empty?

    puts "\nTesting #{orgs.count} organizations..."
    results = { found: [], not_found: [], errors: [] }

    orgs.each_with_index do |org, i|
      puts "\n[#{i + 1}/#{orgs.count}] Testing: #{org.name}"
      begin
        email, _ = find_email_for_org(org)
        if email
          results[:found] << { org: org, email: email }
          puts "  ✓ FOUND: #{email}"
        else
          results[:not_found] << org
          puts "  ○ NOT FOUND"
        end
      rescue => e
        results[:errors] << { org: org, error: e.message }
        puts "  ✗ ERROR: #{e.message.truncate(100)}"
      end
      sleep TEST_MULTIPLE_DELAY
    end

    print_header("TEST RESULTS SUMMARY")
    puts "Total tested: #{orgs.count}"
    puts "✓ Emails found: #{results[:found].length}"
    puts "○ Not found: #{results[:not_found].length}"
    puts "✗ Errors: #{results[:errors].length}"

    if results[:found].any?
      puts "\n--- Emails Found ---"
      results[:found].each { |res| puts "• #{res[:org].name}: #{res[:email]}" }
    end
  end
end
