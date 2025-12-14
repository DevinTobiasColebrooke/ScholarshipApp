# lib/tasks/outreach_sending.rake
require_relative "email_outreach/helpers"

namespace :email_outreach do
  desc "Sends emails in batches to organizations marked for outreach."
  task :send_emails, [ :batch_size ] => :environment do |_, args|
    extend EmailOutreachHelpers

    # Set the batch size from arguments, default to 20. "all" will process all.
    batch_size = args[:batch_size]&.to_i unless args[:batch_size] == "all"
    batch_size ||= GMAIL_CONFIG[:recommended_batch_size]

    # Safety check: don't exceed daily limit
    if batch_size > GMAIL_CONFIG[:daily_limit]
      puts "⚠️  WARNING: Batch size (#{batch_size}) exceeds daily limit (#{GMAIL_CONFIG[:daily_limit]})"
      print "Continue anyway? (yes/no): "
      response = STDIN.gets.chomp.downcase
      abort("Cancelled.") unless response == "yes"
    end

    print_header("BATCH EMAIL SENDING TASK")

    # --- TARGETING LOGIC ---
    outreach_query = OutreachContact.where(status: "ready_for_email_outreach")
                                    .joins(:organization)
                                    .where.not(contact_email: nil)
                                    .order("outreach_contacts.id")

    # Apply the batch limit
    outreach_query = outreach_query.limit(batch_size) if args[:batch_size] != "all"

    contacts_to_process = outreach_query.to_a

    if contacts_to_process.empty?
      abort("\n✓ No organizations are currently marked for email outreach.")
    end

    total_for_this_run = contacts_to_process.count
    puts "\nFound #{total_for_this_run} organizations to email in this batch."
    puts "[MODE: Batch size set to #{batch_size}]"
    puts "[SENDING FROM: #{GMAIL_CONFIG[:from_email]}]"

    sleep_duration = GMAIL_CONFIG[:rate_limit_seconds]

    puts "\nStarting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    print_header("SENDING BATCH STARTED")

    stats = { sent: 0, failed: 0, skipped: 0 }

    contacts_to_process.each_with_index do |contact, index|
      organization = contact.organization
      puts "\n(#{index + 1}/#{total_for_this_run}) Processing: #{organization.name} (Contact ID: #{contact.id})"
      puts "  Campaign: #{contact.campaign_name || 'N/A'}"

      begin
        email_to = contact.contact_email || contact.inferred_contact_email

        unless email_to
          puts "  -> ✗ SKIPPED: No email address available."
          contact.update!(status: "needs_mailing")
          stats[:skipped] += 1
          next
        end

        # --- SEND EMAIL USING ACTION MAILER ---
        mail = OutreachMailer.scholarship_inquiry(contact)

        puts "  -> Sending to: #{email_to}"
        puts "     Subject: #{mail.subject}"

        # Actually deliver the email
        mail.deliver_now

        # --- UPDATE STATE ON SUCCESS ---
        contact.update!(
          status: "pending",
          last_contact_at: Time.current
        )

        # --- LOG THE ACTION ---
        OutreachLog.create!(
          outreach_contact: contact,
          log_type: "email_sent",
          details: "Successfully sent email to #{email_to}\n\nSubject: #{mail.subject}"
        )

        stats[:sent] += 1
        puts "  -> ✓ SUCCESS: Email sent. Status now 'pending' (awaiting response)."

        if index < total_for_this_run - 1
          puts "  (Sleeping for #{sleep_duration} seconds...)"
          sleep(sleep_duration)
        end

      rescue => e
        stats[:failed] += 1
        puts "  -> ✗ ERROR: #{e.class} - #{e.message}"
        puts "     #{e.backtrace.first(3).join("\n     ")}"

        OutreachLog.create!(
          outreach_contact: contact,
          log_type: "status_update",
          details: "Failed to send email: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
        )
      end
    end

    print_header("BATCH SENDING COMPLETE!")
    puts "\nResults for this run:"
    puts "  ✓ Emails sent: #{stats[:sent]}"
    puts "  ✗ Emails failed: #{stats[:failed]}"
    puts "  ⊘ Skipped: #{stats[:skipped]}" if stats[:skipped] > 0

    remaining_count = OutreachContact.where(status: "ready_for_email_outreach").count
    puts "\n#{remaining_count} emails remaining to be sent in future runs."

    puts "\nCurrent status breakdown:"
    OutreachContact.group(:status).count.each do |status, count|
      puts "  #{status.humanize}: #{count}"
    end

    puts "\n💡 TIP: To send more, run: bundle exec rake email_outreach:send_emails[#{GMAIL_CONFIG[:recommended_batch_size]}]"
  end
end
