require_relative "irs_importer/xml_extractor"

namespace :irs do
  desc "Imports XML Data for Missions, Website, and Grants (Only FULL Forms: 990/990-EZ/990-PF/990-O) - Recursively searches subdirectories."
  task import_xml_data: :environment do
    xml_directory = ENV["XML_DIR"] || Rails.root.join("xml")

    puts "--- Starting FULL XML Import (Recursive) from #{xml_directory} ---"

    Rails.logger.level = :info

    file_count = 0

    # *** IMPORTANT CHANGE: Use recursive glob pattern ***
    # This finds all .xml files in all subdirectories of xml_directory
    Dir.glob(File.join(xml_directory, "**", "*.xml")).each do |xml_file|
      # Skip if the path points to a file that is not directly readable or is a symbolic link target, if necessary
      next unless File.file?(xml_file)

      extractor = IrsImporter::XmlExtractor.new(xml_file)

      # Only call the full processing method
      if extractor.process_full_form!
        file_count += 1
      elsif IrsImporter::XmlExtractor::HEADER_ONLY_TYPES.include?(extractor.extract_return_type)
        # We skip 990T here as they are handled by a separate task.
        next
      end

      print "." if file_count % 100 == 0
    end
    puts "\n--- FULL XML Imports Complete. Processed #{file_count} files. ---"
  end
end
