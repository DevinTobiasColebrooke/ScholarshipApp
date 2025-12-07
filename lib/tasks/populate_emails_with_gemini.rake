require_relative "email_outreach/helpers"

namespace :scholarship_app do
  extend EmailOutreachHelpers

  desc "Populate organization emails using Google Gemini. Pass 'free_tier' for rate-limited execution, or 'reprocess_white_woman_profile' to reprocess specific organizations."
  task :populate_emails_with_gemini, [ :mode ] => :environment do |_task, args|
    mode = args[:mode]&.downcase
    free_tier_mode = mode == "free_tier"
    reprocess_wwp_mode = mode == "reprocess_white_woman_profile"

    organizations_to_process = if reprocess_wwp_mode
      puts "Running in 'reprocess_white_woman_profile' mode. Reprocessing all organizations matching the profile."
      Organization.profile_white_woman_26.order(:id)
    else
      # Default mode: Resume where we left off by excluding organizations that already have an outreach contact for this campaign
      processed_org_ids = OutreachContact.where(campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME).select(:organization_id)
      Organization.profile_white_woman_26.where(org_contact_email: [ nil, "" ]).where.not(id: processed_org_ids).order(:id)
    end

    service, sleep_duration = if free_tier_mode && !reprocess_wwp_mode
      puts "Running in free-tier mode. Using 'gemini-2.0-flash' with rate limiting."
      # Gemini 2.0 Flash free tier: 15 RPM, 200 RPD.
      # We'll target 12 RPM (5s sleep) and limit to 190 records per run to be safe.
      organizations_to_process = organizations_to_process.limit(190)
      [ GoogleGeminiService.new(model: "gemini-2.0-flash"), 5 ]
    elsif reprocess_wwp_mode # No rate limiting for reprocess mode unless free_tier is explicitly also passed
      puts "Running 'reprocess_white_woman_profile' in normal (no rate limit) mode."
      [ GoogleGeminiService.new, 0 ]
    else
      puts "Running in normal mode. Using 'gemini-pro'."
      [ GoogleGeminiService.new, 0 ]
    end

    puts "Found #{organizations_to_process.count} organizations to process."

    organizations_to_process.each do |organization|
      puts "Finding email for #{organization.name} (ID: #{organization.id}, EIN: #{organization.ein || 'N/A'}, Address: #{organization.us_address || 'N/A'})..."
      email, raw_response = service.find_email_for_organization(organization.name, organization.ein, organization.us_address, organization.contributing_manager_nm)

      if email.present?
        organization.update(org_contact_email: email)
        puts "  -> Found and updated email: #{email}"
        # For reprocess mode, if an email is found, we create/update the OutreachContact
        OutreachContact.find_or_create_by(organization: organization, campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME) do |contact|
          contact.status = "ready_for_email_outreach"
          contact.contact_email = email
        end
      else
        puts "  -> Email not found for #{organization.name}."
        puts "     (Gemini response: '#{raw_response}')" if raw_response.present?
        # For reprocess mode, if email not found, we create/update OutreachContact to needs_mailing
        OutreachContact.find_or_create_by(organization: organization, campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME) do |contact|
          contact.status = "needs_mailing"
        end
      end

      sleep(sleep_duration) if sleep_duration > 0
    end

    puts "Finished processing organizations."
  end

  desc "Test finding an email for a single organization using Google Gemini"
  task test_gemini_email_finder: :environment do
    puts "--- Starting Single Organization Email Find Test ---"

    # Find the first organization that needs an email and has identifying info
    organization_to_test = Organization.profile_white_woman_26.where(org_contact_email: [ nil, "" ]).order(:id).first

    if organization_to_test.nil?
      puts "No organizations found that need an email. Test cannot run."
      puts "Please ensure you have at least one organization with a nil 'org_contact_email'."
      next
    end

    puts "\n[1] Selecting organization to test:"
    puts "  - Name:    #{organization_to_test.name}"
    puts "  - EIN:     #{organization_to_test.ein}"
    puts "  - Address: #{organization_to_test.us_address}"
    puts "  - Manager: #{organization_to_test.contributing_manager_nm || 'None'}"
    puts "  - Current Email: #{organization_to_test.org_contact_email || 'None'}"

    puts "\n[2] Calling GoogleGeminiService..."
    begin
      service = GoogleGeminiService.new
      email, raw_response = service.find_email_for_organization(
        organization_to_test.name,
        organization_to_test.ein,
        organization_to_test.us_address,
        organization_to_test.contributing_manager_nm
      )

      puts "\n[3] Result from service:"
      if email.present?
        puts "  -> SUCCESS: Found email '#{email}'"
      elsif raw_response.present?
        puts "  -> INFO: Service returned a non-email response: '#{raw_response}'"
      else
        puts "  -> INFO: Email not found by the service (no response)."
      end
    rescue GoogleGeminiService::Error => e
      puts "  -> ERROR: #{e.message}"
      puts "  Please ensure your GOOGLE_GEMINI_KEY is set correctly in credentials."
    rescue => e
      puts "  -> UNEXPECTED ERROR: #{e.class} - #{e.message}"
      puts "  " + e.backtrace.join("\n  ")
    end

    puts "\n--- Test Complete ---"
    puts "Note: This was a dry run. No changes were saved to the database."
  end

  desc "Populate organization emails using the Gemini 2.5 Pro model for testing purposes."
  task :populate_emails_with_gemini_2_5_pro, [] => :environment do
    puts "--- Starting email population with gemini-2.5-pro (Test Task) ---"

    # Gemini 2.5 Pro (Free Tier) limits: 2 RPM, 50 RPD.
    # We'll target 2 RPM (30s sleep) and limit to 40 records to be safe.
    sleep_duration = 30
    record_limit = 40
    campaign_name_2_5 = "#{EmailOutreachHelpers::CAMPAIGN_NAME}_2.5_pro_test"

    # Exclude orgs that have an outreach contact for this specific test campaign
    processed_org_ids = OutreachContact.where(campaign_name: campaign_name_2_5).select(:organization_id)
    organizations_to_process = Organization.profile_white_woman_26.where(org_contact_email: [ nil, "" ])
                                           .where.not(id: processed_org_ids)
                                           .order(:id)
                                           .limit(record_limit)

    puts "Found #{organizations_to_process.count} new organizations to process."

    if organizations_to_process.empty?
      puts "No new organizations to process for this test run."
      puts "--- Finished ---"
      next
    end

    service = GoogleGeminiService.new(model: "gemini-2.5-pro")

    organizations_to_process.each do |organization|
      puts "Finding email for #{organization.name} (ID: #{organization.id},"
      puts "  EIN: #{organization.ein || 'N/A'}, Address: #{organization.us_address || 'N/A'},"
      puts "  Manager: #{organization.contributing_manager_nm || 'N/A'})..."
      email, raw_response = service.find_email_for_organization(
        organization.name,
        organization.ein,
        organization.us_address,
        organization.contributing_manager_nm
      )

      if email.present?
        organization.update(org_contact_email: email)
        puts "  -> Found and updated email: #{email}"
        OutreachContact.find_or_create_by(organization: organization, campaign_name: campaign_name_2_5) do |contact|
          contact.status = "ready_for_email_outreach"
          contact.contact_email = email
        end
      else
        puts "  -> Email not found for #{organization.name}."
        puts "     (Gemini response: '#{raw_response}')" if raw_response.present?
        OutreachContact.find_or_create_by(organization: organization, campaign_name: campaign_name_2_5) do |contact|
          contact.status = "needs_mailing"
        end
      end

      puts "  (Sleeping for #{sleep_duration} seconds to respect rate limits...)"
      sleep(sleep_duration)
    end

    puts "--- Finished processing organizations for gemini-2.5-pro test ---"
  end
end
