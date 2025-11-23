namespace :email_outreach do
  desc "Test email search with a single organization"
  task test_search: :environment do
    puts "="*60
    puts "TESTING EMAIL SEARCH SERVICE"
    puts "="*60

    # Reset any previous daily limit flags
    EmailSearchService.reset_daily_limit_flag

    # Find a test organization
    org = Organization.profile_white_woman_26.first

    if org.nil?
      puts "ERROR: No organizations found matching the profile"
      exit 1
    end

    puts "\nTest Organization:"
    puts "  Name: #{org.name}"
    puts "  EIN: #{org.ein}"
    puts "  Website: #{org.website_address_txt || 'Not in database - AI will search'}"
    if org.contributing_manager_nm.present?
      puts "  Contributing Manager: #{org.contributing_manager_nm}"
    end

    puts "\nAttempting to find email..."
    puts "(This may take a few seconds as the AI searches the web)"

    start_time = Time.now

    begin
      email = EmailSearchService.new(org).find_email
      elapsed = (Time.now - start_time).round(2)

      puts "\n" + "="*60
      if email
        puts "✓ SUCCESS! Email found in #{elapsed} seconds"
        puts "="*60
        puts "Email: #{email}"
        puts "\nThe service is working correctly!"
      else
        puts "○ NO EMAIL FOUND (in #{elapsed} seconds)"
        puts "="*60
        puts "The service is working, but no email was found for this organization."
        puts "This is normal - not all organizations have publicly listed emails."
      end

      puts "\nAPI Response Time: #{elapsed} seconds"
      puts "Current Model: #{EmailSearchService.current_model[:name]}"

    rescue EmailSearchService::DailyLimitReached => e
      puts "\n" + "!"*60
      puts "SERVICE TEMPORARILY UNAVAILABLE"
      puts "!"*60
      puts "The local LLM server is temporarily unavailable or experiencing issues."
      puts "Please ensure your local LLM server is running and try again."

    rescue => e
      puts "\n" + "!"*60
      puts "ERROR"
      puts "!"*60
      puts "Error class: #{e.class}"
      puts "Error message: #{e.message}"
      puts "\nPlease check:"
      puts "  1. Is GEMINI_API_KEY set in your environment?"
      puts "  2. Is the API key valid?"
      puts "  3. Do you have internet connectivity?"
    end
  end

  desc "Test connection to local LLM server and model availability"
  task test_llm_connection: :environment do
    puts "="*60
    puts "TESTING LOCAL LLM SERVER CONNECTION AND MODEL AVAILABILITY"
    puts "="*60

    # Ensure EmailSearchService is loaded to access its configurations
    require_relative '../../app/services/email_search_service'

    llm_base_url = EmailSearchService::LLM_BASE_URL
    llm_api_key = EmailSearchService::LLM_API_KEY
    llm_model_name = EmailSearchService::LLM_MODEL_NAME

    puts "Attempting to connect to LLM server at: #{llm_base_url}"
    puts "Expected model name: #{llm_model_name}"

    begin
      llm_client = OpenAI::Client.new(access_token: llm_api_key, uri_base: llm_base_url)

      # Option 1: List models (if supported by the local LLM server)
      # This is often not fully implemented in local OpenAI-compatible servers
      # models_response = llm_client.models.list
      # available_models = models_response['data'].map { |m| m['id'] }
      # puts "Available models reported by server: #{available_models.join(', ')}" if available_models.any?
      # puts "Is expected model '#{llm_model_name}' available? #{available_models.include?(llm_model_name)}"

      # Option 2: Make a simple chat completion request (more robust test)
      puts "\nAttempting a simple chat completion request..."
      messages = [{ role: "user", content: "Hello, what is your name?" }]
      response = llm_client.chat(
        parameters: { model: llm_model_name, messages: messages, temperature: 0.1, max_tokens: 20 }
      )

      if response && response.dig("choices", 0, "message", "content").present?
        puts "\n✓ SUCCESS: Successfully connected to LLM server and received a response."
        puts "LLM responded: \"#{response.dig("choices", 0, "message", "content").strip}\""
        puts "The local LLM service appears to be working correctly."
      else
        puts "\n✗ FAILURE: Connected to LLM server but received an unexpected or empty response."
        puts "Full response: #{response.inspect}"
        puts "This might indicate a problem with the model or its configuration on the server."
      end

    rescue Faraday::ConnectionFailed => e
      puts "\n✗ FAILURE: Could not connect to LLM server."
      puts "Error: #{e.message}"
      puts "Please ensure your local LLM server is running and accessible at #{llm_base_url}."
    rescue OpenAI::ConfigurationError => e
      puts "\n✗ FAILURE: OpenAI client configuration error."
      puts "Error: #{e.message}"
      puts "Check LLM_BASE_URL and LLM_API_KEY in EmailSearchService."
    rescue Faraday::ClientError => e # Catches 4xx, 5xx errors from the LLM server
      puts "\n✗ FAILURE: LLM server returned an error response."
      parsed_error = JSON.parse(e.response[:body]) rescue { "error" => { "message" => e.message } }
      puts "HTTP Status: #{e.response[:status]}"
      puts "Error Message: #{parsed_error.dig("error", "message")}"
      puts "This often means the model '#{llm_model_name}' is not found or not loaded on the server."
      puts "Please ensure the model is correctly configured and running on your local LLM server."
    rescue StandardError => e
      puts "\n✗ FAILURE: An unexpected error occurred."
      puts "Error class: #{e.class}"
      puts "Error message: #{e.message}"
    end
    puts "\n" + "="*60
  end

  desc "Test email search with multiple organizations to see success rate"
  task test_multiple: :environment do
    puts "="*60
    puts "TESTING EMAIL SEARCH WITH MULTIPLE ORGANIZATIONS"
    puts "="*60

    EmailSearchService.reset_daily_limit_flag

    # Test with 5 organizations
    test_count = 5
    organizations = Organization.profile_white_woman_26.limit(test_count).to_a

    if organizations.empty?
      puts "ERROR: No organizations found"
      exit 1
    end

    puts "\nTesting #{test_count} organizations to gauge success rate..."
    puts "This will take ~#{test_count * 6} seconds (6 seconds per search)"
    puts "\n"

    results = {
      found: [],
      not_found: [],
      errors: []
    }

    organizations.each_with_index do |org, index|
      puts "\n[#{index + 1}/#{test_count}] Testing: #{org.name}"

      begin
        email = EmailSearchService.new(org).find_email

        if email
          results[:found] << { org: org, email: email }
          puts "  ✓ FOUND: #{email}"
        else
          results[:not_found] << org
          puts "  ○ NOT FOUND"
        end
      rescue => e
        results[:errors] << { org: org, error: e.message }
        puts "  ✗ ERROR: #{e.message[0..100]}"
      end

      # Small delay between requests
      sleep 0.5
    end

    # Summary
    puts "\n" + "="*60
    puts "TEST RESULTS SUMMARY"
    puts "="*60
    puts "Total tested: #{test_count}"
    puts "✓ Emails found: #{results[:found].length} (#{(results[:found].length.to_f / test_count * 100).round(1)}%)"
    puts "○ Not found: #{results[:not_found].length} (#{(results[:not_found].length.to_f / test_count * 100).round(1)}%)"
    puts "✗ Errors: #{results[:errors].length}"

    if results[:found].any?
      puts "\n" + "-"*60
      puts "Emails Found:"
      puts "-"*60
      results[:found].each do |result|
        puts "• #{result[:org].name}"
        puts "  Email: #{result[:email]}"
      end
    end

    puts "\n" + "="*60
    puts "The service is working! You can now run the full search:"
    puts "  rake email_outreach:find_emails[10]  # Test with 10 orgs"
    puts "  rake email_outreach:find_emails      # Run full search"
    puts "="*60
  end

  desc "Find and store email addresses for organizations in the 'White Woman/26 Profile' campaign"
  task find_emails: :environment do |task, args|
    # Optional limit parameter for testing: rake email_outreach:find_emails[10]
    limit = args.extras.first&.to_i

    puts "="*60
    puts "EMAIL SEARCH FOR 'WHITE WOMAN/26 PROFILE' CAMPAIGN (using local LLM)"
    puts "="*60
    puts "Note: Rate limiting is applied to control local LLM requests."

    # Reset the daily limit flag at the start
    EmailSearchService.reset_daily_limit_flag

    processed_org_ids = OutreachContact.where(campaign_name: "White Woman/26 Profile").pluck(:organization_id)

    # Include ALL organizations - let the AI search even without website info
    organizations_query = Organization.profile_white_woman_26
                                      .where.not(id: processed_org_ids)

    organizations_query = organizations_query.limit(limit) if limit && limit > 0
    organizations = organizations_query.to_a

    total_orgs = organizations.count

    if total_orgs == 0
      puts "\n✓ All organizations have been processed!"
      puts "No remaining organizations to search."
      exit 0
    end

    estimated_minutes = (total_orgs / 60.0).ceil
    puts "\n#{total_orgs} organizations to process."
    puts "Estimated time: ~#{estimated_minutes} minutes at 60 requests/minute (for local LLM)"

    if limit && limit > 0
      puts "\n[TEST MODE: Limited to #{limit} organizations]"
    end

    puts "\nNote: AI will search the web for ALL organizations, even those without website info in our database."
    puts "If the local LLM becomes unavailable or hits internal limits, the task will stop immediately."
    puts "You can resume by running this task again - it will skip already processed organizations."

    # Show first few organizations that will be processed
    puts "\nFirst organizations to process:"
    organizations.first(3).each_with_index do |org, i|
      website_info = if org.website_address_txt.present? && !org.website_address_txt.match?(/n\/?a/i)
        org.website_address_txt
      else
        "Will search web"
      end
      puts "  #{i + 1}. #{org.name} - #{website_info}"
    end
    puts "  ..." if organizations.count > 3

    puts "\nStarting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    puts "\n" + "="*60
    puts "PROCESSING STARTED"
    puts "="*60

    found_emails = 0
    not_found_emails = 0
    errors = 0
    service_unavailable_hit = false # Changed from daily_limit_hit
    processing_stopped = false
    mutex = Mutex.new

    # Use 3 threads to handle I/O concurrency while respecting rate limit
    num_threads = 3
    queue = Queue.new

    # Enqueue all organizations
    organizations.each { |org| queue << org }
    num_threads.times { queue << :done }

    start_time = Time.now

    # Create worker threads
    threads = num_threads.times.map do |thread_num|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          loop do
            # Check if we should stop processing
            should_stop = mutex.synchronize { processing_stopped }
            break if should_stop

            organization = queue.pop
            break if organization == :done

            # Double-check after popping
            should_stop = mutex.synchronize { processing_stopped }
            if should_stop
              queue << organization # Put it back
              break
            end

            # Show what we're working on
            current_count = mutex.synchronize { found_emails + not_found_emails + errors + 1 }
            website_display = if organization.website_address_txt.present? && !organization.website_address_txt.match?(/n\/?a/i)
              organization.website_address_txt
            else
              "Will search web"
            end

            puts "\n[#{current_count}/#{total_orgs}] Processing: #{organization.name}"
            puts "    Website Info: #{website_display}"

            begin
              # This should call the Gemini API with Google Search
              email = EmailSearchService.new(organization).find_email

              mutex.synchronize do
                if email
                  organization.update(recipient_email_address_txt: email)
                  OutreachContact.find_or_create_by(organization: organization) do |contact|
                    contact.status = 'ready_for_email_outreach'
                    contact.contact_email = email
                    contact.campaign_name = "White Woman/26 Profile"
                  end
                  found_emails += 1
                  puts "    ✓ FOUND: #{email}"
                else
                  OutreachContact.find_or_create_by(organization: organization) do |contact|
                    contact.status = 'needs_mailing'
                    contact.campaign_name = "White Woman/26 Profile"
                  end
                  not_found_emails += 1
                  puts "    ○ NOT FOUND (will need physical mailing)"
                end

                processed = found_emails + not_found_emails + errors
                elapsed = Time.now - start_time
                rate = processed / elapsed * 60

                # Show running totals
                puts "    Running totals: ✓#{found_emails} | ○#{not_found_emails} | ✗#{errors} | Rate: #{rate.round(1)} req/min"
              end

            rescue EmailSearchService::DailyLimitReached => e # This exception now indicates local LLM service issues
              mutex.synchronize do
                processing_stopped = true
                service_unavailable_hit = true

                puts "\n" + "!"*60
                puts "! LOCAL LLM SERVICE UNAVAILABLE - STOPPING ALL THREADS"
                puts "!"*60
                puts "The local LLM server appears to be unavailable or has encountered a persistent error."
                puts "All worker threads will stop immediately."
                puts "\nProgress saved:"
                puts "  ✓ Emails found: #{found_emails}"
                puts "  ○ No email found: #{not_found_emails}"
                puts "  ✗ Errors: #{errors}"
                puts "\nTo resume later:"
                puts "  1. Ensure your local LLM server is running and accessible."
                puts "  2. Run: rake email_outreach:find_emails"
                puts "  3. Already processed organizations will be skipped automatically"
                puts "!"*60
              end

              # Clear the rest of the queue to stop other threads faster
              loop do
                break if queue.empty?
                item = queue.pop(true) rescue nil
                break if item.nil? || item == :done
              end
              break

            rescue StandardError => e
              mutex.synchronize do
                errors += 1
                error_msg = "#{e.class}: #{e.message}"
                Rails.logger.error("[Thread #{thread_num}] ERROR for #{organization.name}: #{error_msg}")
                puts "    ✗ ERROR: #{error_msg[0..100]}"

                # If it looks like a quota error we missed, stop processing
                if error_msg.downcase.include?('connection failed') || error_msg.downcase.include?('refused')
                  processing_stopped = true
                  puts "\n" + "!"*60
                  puts "! LLM CONNECTION ERROR - STOPPING"
                  puts "!"*60
                end
              end
            end

            # Small delay to make output readable
            sleep 0.1
          end
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)

    # Final summary
    elapsed_time = ((Time.now - start_time) / 60.0).round(1)
    puts "\n" + "="*60
    if service_unavailable_hit
      puts "TASK STOPPED: LOCAL LLM SERVICE UNAVAILABLE"
    elsif processing_stopped
      puts "TASK STOPPED: ERROR DETECTED"
    else
      puts "EMAIL SEARCH COMPLETE!"
    end
    puts "="*60
    puts "Total time: #{elapsed_time} minutes"
    puts "\nResults:"
    puts "  ✓ Emails found: #{found_emails}"
    puts "  ○ No email (marked for mailing): #{not_found_emails}"
    puts "  ✗ Errors: #{errors}"
    puts "  Total processed: #{found_emails + not_found_emails}"

    remaining_count = total_orgs - (found_emails + not_found_emails + errors)
    if remaining_count > 0
      puts "\nRemaining to process: #{remaining_count} organizations"
      puts "Run 'rake email_outreach:find_emails' to continue."
    end

    if found_emails + not_found_emails > 0
      actual_rate = ((found_emails + not_found_emails) / elapsed_time).round(1)
      puts "\nActual rate achieved: #{actual_rate} requests/minute"
    end

    # Next steps
    if service_unavailable_hit
      puts "\n" + "="*60
      puts "NEXT STEPS:"
      puts "="*60
      puts "The local LLM server appears to be unavailable. To continue:"
      puts "  1. Ensure your local LLM server is running and accessible."
      puts "  2. Run: rake email_outreach:find_emails"
      puts "  3. The task will automatically skip the #{found_emails + not_found_emails} already processed"
    elsif found_emails > 0
      puts "\n" + "="*60
      puts "ORGANIZATIONS READY FOR OUTREACH:"
      puts "="*60
      puts "#{found_emails} organizations now have email addresses!"
      puts "\nTo view them in Rails console:"
      puts "  OutreachContact.where(status: 'ready_for_email_outreach', campaign_name: 'White Woman/26 Profile')"
    end
  end

  desc "Show current progress and statistics"
  task status: :environment do
    puts "="*60
    puts "EMAIL SEARCH CAMPAIGN STATUS"
    puts "="*60

    total_matching = Organization.profile_white_woman_26.count

    ready = OutreachContact.where(
      campaign_name: "White Woman/26 Profile",
      status: 'ready_for_email_outreach'
    ).count

    needs_mailing = OutreachContact.where(
      campaign_name: "White Woman/26 Profile",
      status: 'needs_mailing'
    ).count

    processed = ready + needs_mailing
    remaining = total_matching - processed

    puts "\nTotal organizations matching profile: #{total_matching}"
    puts "\nProcessed: #{processed} (#{(processed.to_f / total_matching * 100).round(1)}%)"
    puts "  ✓ Ready for email outreach: #{ready}"
    puts "  ○ Need physical mailing: #{needs_mailing}"
    puts "\nRemaining to process: #{remaining}"

    if remaining > 0
      estimated_minutes = (remaining / 60.0).ceil
      puts "\nEstimated time to complete: ~#{estimated_minutes} minutes"
      puts "\nTo continue processing, run:"
      puts "  rake email_outreach:find_emails"
    else
      puts "\n✓ All organizations have been processed!"
    end

    # Show some recent results
    if ready > 0
      puts "\n" + "-"*60
      puts "Recent emails found (last 5):"
      puts "-"*60
      OutreachContact.where(
        campaign_name: "White Woman/26 Profile",
        status: 'ready_for_email_outreach'
      ).includes(:organization).order(created_at: :desc).limit(5).each do |contact|
        puts "  • #{contact.organization.name}"
        puts "    Email: #{contact.contact_email}"
      end
    end
  end

  desc "Reset daily limit flag (use if you know limits have reset)"
  task reset_daily_limit: :environment do
    EmailSearchService.reset_daily_limit_flag
    puts "Daily limit flag has been reset. You can now run find_emails again."
  end
end
