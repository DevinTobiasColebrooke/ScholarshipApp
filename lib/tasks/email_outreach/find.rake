require_relative 'helpers'

namespace :email_outreach do
  extend EmailOutreachHelpers

  desc "Find and store email addresses for organizations in the '#{EmailOutreachHelpers::CAMPAIGN_NAME}' campaign"
  task :find_emails, [:limit] => :environment do |_task, args|
    limit = args[:limit]&.to_i
    print_header("EMAIL SEARCH FOR '#{EmailOutreachHelpers::CAMPAIGN_NAME}' CAMPAIGN")
    puts "Note: Rate limiting is applied to control local LLM requests."
    EmailSearchService.reset_daily_limit_flag

    organizations = unprocessed_organizations(limit: limit)
    total_orgs = organizations.count
    abort("\n✓ All organizations have been processed!") if total_orgs.zero?

    puts "\n#{total_orgs} organizations to process."
    puts "[TEST MODE: Limited to #{limit} organizations]" if limit
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
              email, _ = find_email_for_org(org)
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
end
