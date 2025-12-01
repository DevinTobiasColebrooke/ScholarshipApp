require 'csv'

namespace :irs do
  desc "Outputs EINs of confirmed Scholarship Funders missing detailed XML grant data to a CSV file"
  task list_missing_details: :environment do
    # Generate unique filename
    output_filename = "missing_scholarship_grant_details_#{Time.now.strftime('%Y%m%d%H%M%S')}.csv"

    puts "--- Identifying Confirmed Scholarship Funders (is_scholarship_funder: true) missing XML details ---"

    # 1. Calculate total count first, without selecting specific columns
    total_count = Organization.missing_xml_grant_details.count

    puts "\nTotal Scholarship Funders Missing Detail Data: #{total_count}"

    if total_count == 0
      puts "No organizations found matching the criteria. All current scholarship funders may have XML grant data."
      return
    end

    # 2. Now fetch the organizations, selecting only the necessary columns
    missing_orgs = Organization.missing_xml_grant_details.select(:ein, :name)

    # Write data to CSV
    CSV.open(output_filename, "wb") do |csv|
      csv << ["EIN", "Organization Name"] # Header Row

      # Iterate over all organizations
      missing_orgs.each do |org|
        csv << [org.ein, org.name]
      end
    end

    puts "--- Output Complete ---"
    puts "Data successfully written to #{output_filename}"
  end
end