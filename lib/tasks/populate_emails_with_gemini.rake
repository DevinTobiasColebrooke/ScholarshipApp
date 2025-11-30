# lib/tasks/populate_emails_with_gemini.rake
namespace :scholarship_app do
  desc "Populate organization emails using Google Gemini"
  task populate_emails_with_gemini: :environment do
    organizations_to_update = Organization.where(email: [nil, ""])

    organizations_to_update.each do |organization|
      puts "Finding email for #{organization.name}..."
      email = GoogleGeminiService.new.find_email_for_organization(organization.name, organization.website_address)

      if email.present?
        organization.update(email: email)
        puts "  -> Found and updated email: #{email}"
      else
        puts "  -> Email not found for #{organization.name}"
      end
    end
  end
end
