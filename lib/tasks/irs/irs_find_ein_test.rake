require "nokogiri"
require_relative "irs_importer/xml_extractor"

namespace :irs do
  desc "Tests search for a specific EIN using Ruby/Nokogiri (Usage: EIN=123456789 XML_DIR=/path/to/xml bin/rails irs:find_ein_test)"
  task find_ein_test: :environment do
    target_ein = ENV["EIN"]
    xml_directory = ENV["XML_DIR"] || Rails.root.join("xml")

    unless target_ein.present?
      puts "ERROR: EIN environment variable must be set."
      exit 1
    end

    puts "--- Starting Ruby/Nokogiri search for EIN #{target_ein} in #{xml_directory} ---"
    start_time = Time.now
    found = false
    search_count = 0

    Dir.glob(File.join(xml_directory, "*.xml")).each do |xml_file|
      search_count += 1

      begin
        # Use the reusable XmlExtractor class
        extractor = IrsImporter::XmlExtractor.new(xml_file)

        # Check if the document loaded and then extract the EIN using the helper method
        if extractor.instance_variable_get(:@doc) # Check if XML was parsed successfully
          ein = extractor.extract_text("//EIN")
        else
          ein = nil
        end

        if ein == target_ein
          puts "\nSUCCESS! Found EIN #{target_ein} in file (Ruby):"
          puts "  -> #{xml_file}"
          found = true
          break
        end
      rescue StandardError
        # Silently skip errors
      end

      print "." if search_count % 500 == 0
    end

    duration = Time.now - start_time
    puts "\nSearch complete. Total files checked: #{search_count} in #{duration.round(2)} seconds."

    unless found
      puts "EIN #{target_ein} was NOT found."
    end
  end
end
