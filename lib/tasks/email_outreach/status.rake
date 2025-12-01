require_relative 'helpers'

namespace :email_outreach do
  extend EmailOutreachHelpers

  desc "Show current progress and statistics for '#{CAMPAIGN_NAME}'"
  task status: :environment do
    print_header("CAMPAIGN STATUS: '#{CAMPAIGN_NAME}'")

    total = target_organizations.count
    ready = OutreachContact.where(campaign_name: CAMPAIGN_NAME, status: 'ready_for_email_outreach').count
    mailing = OutreachContact.where(campaign_name: CAMPAIGN_NAME, status: 'needs_mailing').count
    processed = ready + mailing
    remaining = total - processed

    puts "\nTotal organizations in profile: #{total}"
    puts "Processed: #{processed} (#{(processed.to_f / total * 100).round(1)}%)"
    puts "  ✓ Ready for email: #{ready}"
    puts "  ○ Needs physical mail: #{mailing}"
    puts "\nRemaining to process: #{remaining}"

    if remaining > 0
      puts "\nTo continue, run: rake email_outreach:find_emails"
    else
      puts "\n✓ All organizations have been processed!"
    end

    if ready > 0
      puts "\n--- Recent emails found (last 5) ---"
      OutreachContact.where(campaign_name: CAMPAIGN_NAME, status: 'ready_for_email_outreach')
                     .includes(:organization).order(created_at: :desc).limit(5).each do |contact|
        puts "  • #{contact.organization.name}: #{contact.contact_email}"
      end
    end
  end

  desc "Reset daily limit flag (use if you know limits have reset)"
  task reset_daily_limit: :environment do
    EmailSearchService.reset_daily_limit_flag
    puts "Daily limit flag has been reset. You can now run find_emails again."
  end
end
