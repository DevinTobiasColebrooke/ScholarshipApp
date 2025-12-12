require_relative "irs_importer/xml_extractor"

namespace :irs do
  desc "Imports or updates Organization records from 990T XML files (Header + UBI Deductions)"
  task import_xml_990t: :environment do
    xml_directory = ENV["XML_DIR"] || Rails.root.join("data", "xml")

    puts "--- Starting 990-T XML Import from #{xml_directory} ---"

    Dir.glob("#{xml_directory}/*.xml").each do |xml_file|
      extractor = IrsImporter::XmlExtractor.new(xml_file)
      next unless extractor.extract_return_type == "990T"

      ein = extractor.extract_text("//EIN")
      next unless ein.present?

      if extractor.setup_organization(ein)
        updater = IrsImporter::PersistenceUpdater.new(extractor.organization)

        # 1. Update all organization fields (now includes Charitable Deduction)
        updater.update_organization(extractor.extract_organization_fields)

        # NOTE: Supplemental info model update is removed as the data is not in the XML.

        Rails.logger.info "Processed 990-T for EIN #{ein}."
      end
    end
    puts "--- 990-T Imports Complete ---"
  end
end
