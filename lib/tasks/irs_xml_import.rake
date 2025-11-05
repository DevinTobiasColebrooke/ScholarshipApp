require_relative 'irs_importer/xml_extractor'

namespace :irs do
  desc "Imports XML Data for Missions, Website, and Grants (Only FULL Forms: 990/990-EZ/990-PF/990-O)"
  task import_xml_data: :environment do
    xml_directory = ENV["XML_DIR"] || Rails.root.join("data", "xml")

    puts "--- Starting FULL XML Import from #{xml_directory} ---"

    Rails.logger.level = :info

    file_count = 0
    target_ein = '391890044'

    Dir.glob("#{xml_directory}/*.xml").each do |xml_file|
      extractor = IrsImporter::XmlExtractor.new(xml_file)

      # Only call the full processing method
      if extractor.process_full_form!
        file_count += 1

        if extractor.organization && extractor.organization.ein == target_ein
            puts "--- DEBUG: Target EIN #{target_ein} Processed ---"
            puts "App Materials: #{extractor.organization.application_materials_txt}"
            puts "Grants Count: #{extractor.organization.grants.count}"
            puts "------------------------------------------------"
        end
      elsif IrsImporter::XmlExtractor::HEADER_ONLY_TYPES.include?(extractor.extract_return_type)
        # We explicitly skip 990T here, as they are handled by the separate task.
        # This prevents unnecessary logging during the main batch run.
        next
      end

      print '.' if file_count % 100 == 0
    end
    puts "\n--- FULL XML Imports Complete. Processed #{file_count} files. ---"
  end
end
