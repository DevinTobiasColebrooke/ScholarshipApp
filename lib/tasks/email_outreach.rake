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
      puts "DAILY LIMIT REACHED"
      puts "!"*60
      puts "Your API key has reached its daily quota."
      puts "Wait until the quota resets (typically midnight Pacific Time) and try again."

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
    puts "EMAIL SEARCH FOR 'WHITE WOMAN/26 PROFILE' CAMPAIGN"
    puts "="*60
    puts "Rate limit: 60 requests per minute (free tier)"

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
    puts "Estimated time: ~#{estimated_minutes} minutes at 60 requests/minute"

    if limit && limit > 0
      puts "\n[TEST MODE: Limited to #{limit} organizations]"
    end

    puts "\nNote: AI will search the web for ALL organizations, even those without website info in our database."
    puts "If daily API limits are reached, the task will stop immediately."
    puts "You can resume by running this task again - it will skip already processed organizations."

    # Show first few organizations that will be processed
    puts "\nFirst organizations to process:"
    organizations.first(3).each_with_index do |org, i|
      website_info = if org.website_address_txt.present? && !org.website_address_txt.match?(/n\/?a/i)
        org.website_address_txt
      else
        "No website in DB (AI will search)"
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
    daily_limit_hit = false
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

            rescue EmailSearchService::DailyLimitReached => e
              mutex.synchronize do
                processing_stopped = true
                daily_limit_hit = true

                puts "\n" + "!"*60
                puts "! DAILY API LIMIT REACHED - STOPPING ALL THREADS"
                puts "!"*60
                puts "All available Gemini models have reached their daily quota."
                puts "All worker threads will stop immediately."
                puts "\nProgress saved:"
                puts "  ✓ Emails found: #{found_emails}"
                puts "  ○ No email found: #{not_found_emails}"
                puts "  ✗ Errors: #{errors}"
                puts "\nTo resume later:"
                puts "  1. Wait for the daily quota to reset (typically midnight Pacific Time)"
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
                if error_msg.downcase.include?('quota') || error_msg.downcase.include?('limit')
                  processing_stopped = true
                  puts "\n" + "!"*60
                  puts "! POSSIBLE QUOTA ERROR DETECTED - STOPPING"
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
    if daily_limit_hit
      puts "TASK STOPPED: DAILY API LIMIT REACHED"
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
    if daily_limit_hit
      puts "\n" + "="*60
      puts "NEXT STEPS:"
      puts "="*60
      puts "Your API has hit its daily quota. To continue:"
      puts "  1. Wait for quota reset (usually midnight Pacific Time)"
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
