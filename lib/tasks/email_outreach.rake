# frozen_string_literal: true

namespace :email_outreach do
  desc "Find and store email addresses for organizations in the 'White Woman/26 Profile' campaign"
  task find_emails: :environment do
    puts "Starting email search for 'White Woman/26 Profile' campaign..."

    processed_org_ids = OutreachContact.where(campaign_name: "White Woman/26 Profile").pluck(:organization_id)
    organizations = Organization.profile_white_woman_26
                                .where.not(website_address_txt: nil)
                                .where.not(id: processed_org_ids)

    total_orgs = organizations.count
    puts "#{total_orgs} organizations to process."

    found_emails = 0
    not_found_emails = 0

    organizations.find_each.with_index do |organization, index|
      puts "Processing organization #{index + 1}/#{total_orgs}: #{organization.name}"

      email = EmailSearchService.new(organization).find_email

      if email
        organization.update(recipient_email_address_txt: email)
        OutreachContact.find_or_create_by(organization: organization) do |contact|
          contact.status = 'needs_outreach'
          contact.contact_email = email
          contact.campaign_name = "White Woman/26 Profile"
        end
        found_emails += 1
        puts "  Found email: #{email}"
      else
        OutreachContact.find_or_create_by(organization: organization) do |contact|
          contact.status = 'needs_mailing'
          contact.campaign_name = "White Woman/26 Profile"
        end
        not_found_emails += 1
        puts "  Email not found."
      end
    end

    puts "\nEmail search complete."
    puts "Total organizations processed in this run: #{total_orgs}"
    puts "Emails found: #{found_emails}"
    puts "Emails not found (marked for mailing): #{not_found_emails}"
  end
end
