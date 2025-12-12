# lib/tasks/reverify_failures.rake
require_relative "email_outreach/helpers"

namespace :email_outreach do
  desc "Re-verify emails for 'not_found' and previously errored orgs using Gemini 2.5 Pro with Google Search."
  task :reverify_failures_with_gemini_pro, [ :limit ] => :environment do |_, args|
    extend EmailOutreachHelpers

    limit = args[:limit]&.to_i unless args[:limit] == "all"
    
    # Use a dedicated campaign name to track the progress of this specific re-verification task
    REVERIFY_CAMPAIGN_NAME = "White Woman/26 Profile - Gemini Pro Re-verify".freeze

    print_header("RE-VERIFYING FAILURES WITH GEMINI 2.5 PRO & GOOGLE SEARCH")
    
    # --- TARGETING LOGIC ---
    # 1. Get IDs of all orgs in the base scope
    all_target_org_ids = target_organizations.pluck(:id)
    
    # 2. Get IDs of orgs that were successfully processed in the MAIN campaign
    main_campaign_success_ids = OutreachContact.where(
      campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME,
      status: 'ready_for_email_outreach'
    ).pluck(:organization_id)

    # 3. The initial pool of failures is everyone in the scope MINUS the successes
    initial_failure_ids = all_target_org_ids - main_campaign_success_ids

    # 4. Get IDs of orgs that have ALREADY been processed in THIS re-verification run
    already_reverified_ids = OutreachContact.where(campaign_name: REVERIFY_CAMPAIGN_NAME).pluck(:organization_id)

    # 5. The final list to process is the initial failures MINUS those already re-verified
    organizations_to_reprocess_ids = initial_failure_ids - already_reverified_ids
    
    organizations_query = Organization.where(id: organizations_to_reprocess_ids).order(:id)
    
    # Apply limit
    organizations_query = organizations_query.limit(limit) if limit
    organizations = organizations_query.to_a
    
    if organizations.empty?
      abort("\n✓ No 'not_found' or previously errored organizations to re-verify.")
    end

    total_orgs_for_this_run = organizations.count
    puts "\nFound #{total_orgs_for_this_run} organizations to re-verify."
    puts "[MODE: Limited to #{limit} organizations]" if limit

    # Initialize the powerful service
    service = GoogleGeminiService.new(model: "gemini-2.5-pro")
    # Gemini 2.5 Pro has a low free tier RPM (e.g., 2 RPM). We'll add a significant sleep.
    sleep_duration = 30 

    puts "\nStarting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    print_header("RE-PROCESSING STARTED")

    stats = { found: 0, not_found: 0, errors: 0 }

    organizations.each_with_index do |org, index|
      begin
        puts "\n(#{index + 1}/#{total_orgs_for_this_run}) Re-verifying: #{org.name} (ID: #{org.id})"
        email, raw_response = service.find_email_for_organization(
          org.name,
          org.ein,
          org.us_address,
          org.contributing_manager_nm
        )

        # --- Self-contained update logic using the new campaign name ---
        contact = OutreachContact.find_or_initialize_by(organization: org, campaign_name: REVERIFY_CAMPAIGN_NAME)
        if email
          # Overwrite the main organization record email as well
          org.update(org_contact_email: email)
          contact.status = "ready_for_email_outreach"
          contact.contact_email = email
          stats[:found] += 1
          puts "  -> ✓ SUCCESS: Found and updated email to '#{email}'"
        else
          contact.status = "needs_mailing"
          contact.contact_email = nil
          stats[:not_found] += 1
          puts "  -> ○ NOT FOUND. Raw Response: '#{raw_response}'"
        end
        contact.save!
        # --- End of self-contained logic ---

        if index < total_orgs_for_this_run - 1
          puts "  (Sleeping for #{sleep_duration} seconds to respect rate limits...)"
          sleep(sleep_duration)
        end

      rescue => e
        stats[:errors] += 1
        puts "  -> ✗ ERROR: #{e.class} - #{e.message}"
      end
    end

    print_header("RE-VERIFICATION COMPLETE!")
    puts "\nResults:"
    puts "  ✓ Emails found: #{stats[:found]}"
    puts "  ○ Still not found: #{stats[:not_found]}"
    puts "  ✗ Errors: #{stats[:errors]}"
  end
end
