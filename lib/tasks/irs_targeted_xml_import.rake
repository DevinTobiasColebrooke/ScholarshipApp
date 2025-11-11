require 'csv'
require 'nokogiri'
require_relative 'irs_importer/xml_extractor'
require_relative 'irs_importer/persistence_updater'

namespace :irs do
  desc "Performs targeted recursive XML import only for EINs listed in a specified CSV file."
  task targeted_xml_import: :environment do
    csv_file_path = ENV["CSV_PATH"]
    xml_directory = ENV["XML_DIR"]

    unless csv_file_path.present? && xml_directory.present?
      puts "ERROR: Both CSV_PATH and XML_DIR environment variables must be set."
      puts "Usage Example:"
      puts "CSV_PATH=missing_scholarship_grant_details_...csv XML_DIR=/mnt/f/2023 bin/rails irs:targeted_xml_import"
      exit 1
    end

    # --- Step 1: Load Target EINs from CSV ---
    puts "--- Step 1: Loading target EINs from #{csv_file_path} ---"
    target_eins = Set.new
    begin
      CSV.foreach(csv_file_path, headers: true) do |row|
        ein = row["EIN"].to_s.strip
        target_eins.add(ein) if ein.present?
      end
    rescue Errno::ENOENT
      puts "ERROR: CSV file not found at #{csv_file_path}. Aborting."
      exit 1
    end

    puts "Loaded #{target_eins.size} target EINs for recovery."
    if target_eins.empty?
      puts "No EINs found in the CSV. Aborting."
      return
    end

    # --- Step 2: Recursively Scan XML Directory and Import Matches ---
    puts "--- Step 2: Recursively scanning #{xml_directory} for matching XML files ---"

    start_time = Time.now
    files_scanned = 0
    records_updated = 0

    # Use recursive glob pattern
    Dir.glob(File.join(xml_directory, '**', '*.xml')).each do |xml_file|
      files_scanned += 1

      # Use Nokogiri to quickly extract the EIN without full Rails overhead
      begin
        doc = Nokogiri::XML(File.open(xml_file))
        current_ein = doc.at_xpath('//*[local-name()="EIN"]')&.text
      rescue StandardError
        current_ein = nil
      end

      # --- Conditional Import ---
      if current_ein.present? && target_eins.include?(current_ein)

        # Found a match! Now perform the full, heavy import using the existing logic.
        puts "\nMATCH FOUND: #{current_ein} in #{File.basename(xml_file)}. Starting full import..."

        extractor = IrsImporter::XmlExtractor.new(xml_file)

        # We need to manually set up the organization instance since we used Nokogiri above
        if extractor.setup_organization(current_ein)
          updater = IrsImporter::PersistenceUpdater.new(extractor.organization)

          # Perform the full update of core data, programs, and grants
          updater.update_organization(extractor.extract_organization_fields)
          updater.update_program_services(extractor.extract_program_services_data)
          updater.update_grants(extractor.extract_grants_paid_data)

          records_updated += 1
          target_eins.delete(current_ein) # Remove from set to track remaining

          puts "SUCCESS: Updated #{current_ein}. Remaining targets: #{target_eins.size}"
        end
      end

      # Provide periodic status updates on scanning progress
      if files_scanned % 5000 == 0
        elapsed = (Time.now - start_time).round(2)
        puts "\nStatus: Scanned #{files_scanned} files in #{elapsed}s. Updated #{records_updated}. Targets remaining: #{target_eins.size}"
      end

      # If all targets are met, exit early
      break if target_eins.empty?
    end

    duration = (Time.now - start_time).round(2)
    puts "\n--- Targeted Import Complete ---"
    puts "Total files scanned: #{files_scanned}."
    puts "Total records updated: #{records_updated}."
    puts "Time elapsed: #{duration} seconds."

    unless target_eins.empty?
      puts "WARNING: Could not find XML files for #{target_eins.size} target EINs. They may be in another directory."
      puts "Missing EINs (first 10): #{target_eins.to_a.first(10).join(', ')}"
    end
  end
end
