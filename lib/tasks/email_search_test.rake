# lib/tasks/email_search_test.rake
namespace :email_search do
  desc "Test the EmailSearchService for a specific organization"
  task :test, [ :name, :ein, :location ] => :environment do |_, args|
    if args[:name].blank? || args[:ein].blank? || args[:location].blank?
      puts "Usage: rails email_search:test['Organization Name','EIN','City, ST']"
      next
    end

    puts "Starting email search test for: #{args[:name]}"
    puts "EIN: #{args[:ein]}, Location: #{args[:location]}"
    puts "----------------------------------"

    # Find or create the organization
    organization = Organization.find_or_create_by!(name: args[:name], ein: args[:ein]) do |org|
      org.us_address = args[:location]
    end

    if organization.persisted?
      puts "Found or created organization with ID: #{organization.id}"
    else
      puts "Failed to find or create organization."
      next
    end

    # Initialize and run the service
    email_search_service = EmailSearchService.new(organization)

    puts "\nStep 1: Calling EmailSearchService#find_email_with_details..."
    details = email_search_service.find_email_with_details

    puts "\n----------------------------------"
    puts "DEBUGGING INFORMATION"
    puts "----------------------------------"
    puts "Web Search Query:"
    puts details[:web_search_query]
    puts "\nContext Sent to LLM:"
    puts "---"
    puts details[:context] || "No context was generated."
    puts "---\n"
    puts "Raw LLM Response:"
    puts details[:llm_response] || "No response from LLM."

    puts "\n----------------------------------"
    puts "RESULT"
    puts "----------------------------------"

    found_email = details[:email]
    if found_email
      puts "Success! Found email: #{found_email}"
      organization.update(email_address: found_email)
      puts "Updated organization record with the new email."
    else
      puts "Email not found."
    end

    puts "\nEmail search test finished."
  end
end
