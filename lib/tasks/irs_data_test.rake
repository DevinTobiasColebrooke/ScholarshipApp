require_relative 'irs_importer/xml_extractor'
require 'pp'

namespace :irs do
  desc "Extracts and displays data from a single XML file (Usage: XML_FILE=/path/to/file.xml rails irs:test_xml_file)"
  task test_xml_file: :environment do
    file_path = ENV["XML_FILE"]

    unless file_path && File.exist?(file_path)
      puts "ERROR: XML_FILE environment variable not set or file not found."
      puts "Usage: XML_FILE=/path/to/file.xml bin/rails irs:test_xml_file"
      exit 1
    end

    puts "--- Testing extraction of #{File.basename(file_path)} ---"

    # Ensure BigDecimal is included, though Rails environment usually loads it.
    require 'bigdecimal'

    extractor = IrsImporter::XmlExtractor.new(file_path)

    extracted_data = extractor.extract_all_data

    unless extracted_data
      puts "Failed to extract EIN or parse file."
      next
    end

    puts "\n======================================================="
    puts "EIN: #{extracted_data[:ein]}"
    puts "======================================================="

    puts "\n--- ORGANIZATION FIELDS (Core Data) ---"
    pp extracted_data[:organization_fields]

    puts "\n--- PROGRAM SERVICES (#{extracted_data[:program_services].count} found) ---"

    if extracted_data[:program_services].empty?
      puts "None found. (This is common for 990-PF if detailed program service data is elsewhere.)"
    else
      pp extracted_data[:program_services]
    end

    puts "\n--- GRANTS PAID (#{extracted_data[:grants].count} found) ---"

    # Display the first 5 grants for brevity
    display_count = 5
    extracted_data[:grants].first(display_count).each_with_index do |grant, index|
        puts "Grant #{index + 1}:"
        pp grant
    end

    if extracted_data[:grants].count > display_count
      puts "(... #{extracted_data[:grants].count - display_count} more grants suppressed)"
    end

    puts "\n--- Test Complete ---"
  end
end
