namespace :data do
  desc "Nullify org_contact_email if it does not contain an '@' symbol"
  task clean_bad_emails: :environment do
    puts "Scanning for invalid emails..."

    # Find records where email is not null but lacks '@'
    bad_records = Organization.where.not(org_contact_email: nil)
                              .where("org_contact_email NOT LIKE '%@%'")

    count = bad_records.count

    if count > 0
      puts "Found #{count} invalid email entries (likely URLs)."

      # Examples before deleting
      puts "Examples:"
      bad_records.limit(5).each do |org|
        puts "  - #{org.name}: #{org.org_contact_email}"
      end

      # Perform the update
      bad_records.update_all(org_contact_email: nil)

      puts "✓ Cleaned #{count} records. usage: org_contact_email is now NULL."
    else
      puts "✓ No invalid emails found."
    end
  end
end
