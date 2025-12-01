require_relative 'irs_importer/xml_extractor'

namespace :irs do
  desc "Backfills new supplementary info fields from all existing XML files (Part XIV/XV)"
  task backfill_supplementary_info: :environment do
    xml_directory = ENV["XML_DIR"] || Rails.root.join("data", "xml")

    puts "--- Starting Supplementary Info Backfill from #{xml_directory} ---"

    Rails.logger.level = :info

    file_count = 0
    # Use the same filter for FULL processing types as the main import task
    full_processing_types = IrsImporter::XmlExtractor::FULL_PROCESSING_TYPES

    Dir.glob("#{xml_directory}/*.xml").each do |xml_file|
      extractor = IrsImporter::XmlExtractor.new(xml_file)
      return_type = extractor.extract_return_type
      ein = extractor.extract_text("//EIN")

      next unless full_processing_types.include?(return_type) && ein.present?

      organization = Organization.find_by(ein: ein)

      if organization
        # Now safely call the public-scoped method
        extracted_fields = extractor.extract_organization_fields

        if extracted_fields.any?
          # Update the organization, skipping the grant/program service delete/insert
          organization.update!(extracted_fields)
          file_count += 1
          print '.' if file_count % 100 == 0
        end
      end
    end
    puts "\n--- Backfill Complete. Updated #{file_count} organizations. ---"
  end
end