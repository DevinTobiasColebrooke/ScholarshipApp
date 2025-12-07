# lib/tasks/email_outreach.rake
require_relative "email_outreach/helpers"

namespace :email_outreach do
  extend EmailOutreachHelpers

  desc "Find emails using local SearXNG. Multi-threaded. Args: [limit]"
  task :find_emails, [ :limit ] => :environment do |_task, args|
    limit = args[:limit]&.to_i
    print_header("EMAIL SEARCH (SEARXNG) FOR '#{EmailOutreachHelpers::CAMPAIGN_NAME}' CAMPAIGN")
    puts "Using local SearXNG instance. Rate limiting is applied to control local LLM requests."
    EmailSearchService.reset_daily_limit_flag

    organizations = unprocessed_organizations(limit: limit)
    total_orgs = organizations.count
    abort("\n✓ All organizations have been processed!") if total_orgs.zero?

    puts "\n#{total_orgs} organizations to process."
    puts "[MODE: Limited to #{limit} organizations]" if limit
    puts "\nStarting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    print_header("PROCESSING STARTED")

    stats = { found: 0, not_found: 0, errors: 0 }
    processing_stopped = false
    mutex = Mutex.new
    queue = Queue.new
    organizations.each { |org| queue << org }
    NUM_THREADS.times { queue << :done }

    start_time = Time.now
    threads = Array.new(NUM_THREADS) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          loop do
            break if mutex.synchronize { processing_stopped }
            org = queue.pop
            break if org == :done

            begin
              email, _ = find_email_for_org(org, search_provider: :searxng)
              mutex.synchronize do
                update_outreach_contact(org: org, email: email)
                stats[email ? :found : :not_found] += 1
                puts "  #{email ? '✓ FOUND' : '○ NOT FOUND'}: #{org.name} #{email ? "(#{email})" : ''}"
              end
            rescue EmailSearchService::DailyLimitReached => e
              mutex.synchronize do
                processing_stopped = true
                handle_service_unavailable(e)
              end
              break
            rescue => e
              mutex.synchronize do
                stats[:errors] += 1
                puts "  ✗ ERROR: #{org.name} - #{e.message.truncate(100)}"
              end
            end
          end
        end
      end
    end

    threads.each(&:join)

    elapsed_minutes = ((Time.now - start_time) / 60.0).round(1)
    print_header(processing_stopped ? "TASK STOPPED" : "EMAIL SEARCH COMPLETE!")
    puts "Total time: #{elapsed_minutes} minutes"
    puts "\nResults:"
    puts "  ✓ Emails found: #{stats[:found]}"
    puts "  ○ No email (marked for mailing): #{stats[:not_found]}"
    puts "  ✗ Errors: #{stats[:errors]}"
  end


  desc "Find emails using Google Search API. Args: [tier ('free' or 'paid')]"
  task :find_emails_with_google, [ :tier ] => :environment do |_task, args|
    tier = args[:tier]&.downcase || "free"
    is_paid_tier = tier == "paid"
    limit = is_paid_tier ? nil : 100

    print_header("EMAIL SEARCH (GOOGLE API | #{is_paid_tier ? 'PAID' : 'FREE'} TIER) FOR '#{EmailOutreachHelpers::CAMPAIGN_NAME}'")
    EmailSearchService.reset_daily_limit_flag

    organizations = unprocessed_organizations(limit: limit)
    total_orgs = organizations.count
    abort("\n✓ All organizations have been processed for this tier!") if total_orgs.zero?

    puts "\nProcessing #{total_orgs} organizations from '#{EmailOutreachHelpers::CAMPAIGN_NAME}' scope."
    puts "[TIER: #{tier.upcase} | Limit: #{limit || 'None'}]\n"
    puts "Starting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    print_header("PROCESSING STARTED")

    stats = { found: 0, not_found: 0, errors: 0 }
    start_time = Time.now

    organizations.each_with_index do |org, index|
      begin
        puts "\n(#{index + 1}/#{total_orgs}) Processing: #{org.name}"
        email, _ = find_email_for_org(org, search_provider: :google)
        update_outreach_contact(org: org, email: email)
        stats[email ? :found : :not_found] += 1
        puts "  -> #{email ? '✓ FOUND' : '○ NOT FOUND'} #{email ? "(#{email})" : ''}"
      rescue => e
        stats[:errors] += 1
        puts "  -> ✗ ERROR: #{e.message.truncate(100)}"
      end
    end

    elapsed_minutes = ((Time.now - start_time) / 60.0).round(1)
    print_header("GOOGLE API EMAIL SEARCH COMPLETE!")
    puts "Total time: #{elapsed_minutes} minutes"
    puts "\nResults:"
    puts "  ✓ Emails found: #{stats[:found]}"
    puts "  ○ No email (marked for mailing): #{stats[:not_found]}"
    puts "  ✗ Errors: #{stats[:errors]}"
  end

  desc "Find email for a specific organization. Args: [organization_id]"
  task :find_email_for_org, [ :organization_id ] => :environment do |_, args|
    organization_id = args[:organization_id]
    unless organization_id.present?
      puts "Usage: rake 'email_outreach:find_email_for_org[organization_id]'"
      abort("ERROR: An organization ID must be provided.")
    end

    org = Organization.find_by(id: organization_id)
    unless org
      abort("ERROR: Organization with ID #{organization_id} not found.")
    end

    print_header("EMAIL SEARCH FOR SINGLE ORGANIZATION: #{org.name}")
    puts "Using Google Search API."

    begin
      puts "--- CALLING EmailSearchService ---"
      details = EmailSearchService.new(org, search_provider: :google).find_email_with_details
      puts "--- RETURNED FROM EmailSearchService ---"
      puts "Details: #{details.inspect}"

      email = details[:email]

      update_outreach_contact(org: org, email: email)

      puts "  -> #{email ? '✓ FOUND' : '○ NOT FOUND'} #{email ? "(#{email})" : ''}"
      puts "\n--- DEBUG DETAILS ---"
      puts "Initial Search Query: #{details[:web_search_query]}"
      puts "LLM Response: #{details[:llm_response]}"
      puts "Context sent to LLM:\n#{details[:context]}"
      puts "----------------------"

    rescue => e
      puts "  -> ✗ ERROR: #{e.message.truncate(100)}"
      puts "Backtrace:\n#{e.backtrace.first(5).join("\n")}"
    end

    print_header("SINGLE ORGANIZATION EMAIL SEARCH COMPLETE!")
  end
end