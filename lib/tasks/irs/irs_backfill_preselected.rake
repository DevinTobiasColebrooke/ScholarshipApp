require_relative 'irs_importer/xml_extractor'

namespace :irs do
  desc "Backfills 'only_contri_preselected_ind' field for organizations with 990/990PF filings."
  task backfill_preselected_grants: :environment do
    xml_directory = ENV["XML_DIR"] || Rails.root.join("data", "xml")

    puts "--- Starting Backfill of Preselected Grant Indicator from #{xml_directory} ---"

    Rails.logger.level = :info

    update_count = 0
    skip_count = 0

    # We only care about FULL forms (990, 990PF, etc.)
    full_forms = IrsImporter::XmlExtractor::FULL_PROCESSING_TYPES.to_set

    Dir.glob("#{xml_directory}/*.xml").each do |xml_file|
      extractor = IrsImporter::XmlExtractor.new(xml_file)

      doc = extractor.instance_variable_get(:@doc)
      next unless doc # Skip if file failed to load/parse

      return_type = extractor.extract_return_type
      next unless full_forms.include?(return_type)

      ein = extractor.extract_text("//EIN")
      next unless ein.present?

      # Find the organization (no creation needed, this is a backfill task)
      organization = Organization.find_by(ein: ein)
      unless organization
        skip_count += 1
        next
      end

      # --- Focused Extraction ---

      # Extract the indicator directly
      preselected_ind = extractor.extract_text("//OnlyContriToPreselectedInd")

      # We only update if the value is changing OR if it's explicitly 'X'
      if organization.only_contri_preselected_ind != preselected_ind
        organization.update_column(:only_contri_preselected_ind, preselected_ind)

        # NOTE: If preselected_ind is nil, we update the column to nil/NULL.
        # If preselected_ind is 'X', we update the column to 'X'.

        update_count += 1
        Rails.logger.info "Updated EIN #{organization.ein}: only_contri_preselected_ind set to '#{preselected_ind || 'nil'}'"
      end

      print '.' if update_count % 100 == 0
    end

    puts "\n--- Backfill Complete. ---"
    puts "Total records updated: #{update_count}."
    puts "Total records skipped (Missing in DB): #{skip_count}."
  end
end