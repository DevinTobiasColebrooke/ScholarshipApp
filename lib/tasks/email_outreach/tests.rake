require_relative "helpers"

namespace :email_outreach do
  desc "Verify Gmail credentials are configured"
  task check_credentials: :environment do
    puts "\n" + "="*80
    puts "GMAIL CREDENTIALS CHECK"
    puts "="*80

    username = Rails.application.credentials.dig(:gmail, :username)
    password = Rails.application.credentials.dig(:gmail, :app_password)

    puts "\nChecking credentials..."

    if username.blank?
      puts "  ✗ FAILED: gmail.username not found in credentials"
      puts "  Run: EDITOR='code --wait' rails credentials:edit"
      puts "  Add:\n    gmail:\n      username: johanna@johannalucilleroberts.com\n      app_password: YOUR_APP_PASSWORD"
      exit 1
    else
      puts "  ✓ Username configured: #{username}"
    end

    if password.blank?
      puts "  ✗ FAILED: gmail.app_password not found in credentials"
      puts "  Run: EDITOR='code --wait' rails credentials:edit"
      puts "  Add:\n    gmail:\n      username: #{username}\n      app_password: YOUR_16_CHAR_APP_PASSWORD"
      exit 1
    else
      puts "  ✓ App password configured: #{'*' * 16}"
    end

    puts "\n✓ All credentials present!"
    puts "\nNext step: Run test email"
    puts "  bundle exec rake email_outreach:test"
  end

  desc "Send a test email to verify Gmail integration"
  task test: :environment do
    puts "\n" + "="*80
    puts "EMAIL OUTREACH TEST"
    puts "="*80

    # Use a real organization from the database for realistic testing
    test_org = Organization.where.not(org_contact_email: nil).first

    unless test_org
      abort("ERROR: No organizations with email addresses found in database.")
    end

    puts "\nCreating test outreach contact..."
    puts "  Organization: #{test_org.name}"
    puts "  EIN: #{test_org.ein}"

    # Create a temporary test contact
    test_contact = OutreachContact.create!(
      organization: test_org,
      status: :ready_for_email_outreach,
      contact_email: "johanna@johannalucilleroberts.com", # Send to yourself for testing
      campaign_name: "Test Campaign - #{Time.current.strftime('%Y-%m-%d %H:%M')}"
    )

    puts "\nGenerating email..."
    mail = OutreachMailer.scholarship_inquiry(test_contact)

    puts "\n" + "-"*80
    puts "EMAIL DETAILS:"
    puts "-"*80
    puts "  From: #{mail.from.first}"
    puts "  To: #{mail.to.first}"
    puts "  Subject: #{mail.subject}"
    puts "-"*80

    print "\nSending test email..."

    begin
      mail.deliver_now
      puts " ✓ SUCCESS"

      puts "\n✓ Test email sent successfully!"
      puts "\nNext steps:"
      puts "  1. Check johanna@johannalucilleroberts.com inbox"
      puts "  2. Verify email formatting and content"
      puts "  3. Check spam folder if not in inbox"
      puts "  4. If successful, proceed with: bundle exec rake email_outreach:send_emails[20]"

      # Update the test contact status to show it worked
      test_contact.update!(
        status: :pending,
        last_contact_at: Time.current
      )

      test_contact.outreach_logs.create!(
        log_type: "email_sent",
        details: "TEST EMAIL sent to johanna@johannalucilleroberts.com\n\nSubject: #{mail.subject}"
      )

      puts "\n✓ Test contact logged (ID: #{test_contact.id})"
      puts "  View in tracker at: http://localhost:3000/outreach_contacts"

    rescue => e
      puts " ✗ FAILED"
      puts "\nERROR: #{e.class}"
      puts "MESSAGE: #{e.message}"
      puts "\nStack trace:"
      puts e.backtrace.first(5).join("\n")

      puts "\nTROUBLESHOOTING:"
      puts "  1. Verify Gmail credentials are set: rails credentials:edit"
      puts "  2. Check SMTP settings in config/environments/development.rb"
      puts "  3. Ensure app password is correct (16 characters, no spaces)"
      puts "  4. Verify 2FA is enabled on Google Workspace account"

      # Clean up failed test contact
      test_contact.destroy

      exit 1
    end

    puts "\n" + "="*80
    puts "TEST COMPLETE"
    puts "="*80 + "\n"
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
