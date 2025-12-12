require "csv"

namespace :irs do
  # ----------------------------------------------------------------------
  # HELPER METHODS (CSV)
  # ----------------------------------------------------------------------

  # Common encoding for large IRS CSV files to handle non-UTF-8 characters
  CSV_OPTIONS = { headers: true, encoding: "ISO-8859-1:UTF-8" }.freeze

  def import_bmf(file_path)
    data_to_upsert = []

    puts "Reading BMF file: #{File.basename(file_path)}..."

    # Using headers from eo1.csv-eo4.csv
    CSV.foreach(file_path, **CSV_OPTIONS) do |row|
      # Only import if EIN is present
      next unless row["EIN"].present?

      # Mapping BMF headers to Organization model fields
      data_to_upsert << {
        ein: row["EIN"].to_s.strip,
        name: row["NAME"].to_s.strip,
        # BMF Data points: EIN, Name, NTEE Code, PF Filing Requirement
        pf_filing_req_cd: row["PF_FILING_REQ_CD"].to_s.strip,
        ntee_code: row["NTEE_CD"].to_s.strip,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    puts "Inserting/Updating #{data_to_upsert.count} records from #{File.basename(file_path)} into Organizations table..."

    # Use upsert_all for high performance bulk creation/updating based on EIN
    Organization.upsert_all(data_to_upsert, unique_by: :ein)
  end

  def update_from_annual_extract(file_path)
    puts "Reading Annual Extract file from: #{file_path}"
    # Using headers from 24eoextract990pf.csv
    CSV.foreach(file_path, **CSV_OPTIONS) do |row|
      ein = row["EIN"].to_s.strip

      # Only update relevant fields
      update_data = {}
      # SOI Data points: Grants to Individuals, Approved Future Grants
      update_data[:grnt_indiv_cd] = row["GRNTINDIVCD"].to_s.strip if row["GRNTINDIVCD"].present?
      update_data[:grnt_apprv_fut] = row["GRNTAPPRVFUT"].to_s.strip if row["GRNTAPPRVFUT"].present?

      Organization.find_by(ein: ein)&.update(update_data)
    end
  end


  # ----------------------------------------------------------------------
  # RAKE TASK DEFINITION
  # ----------------------------------------------------------------------

  # NEW: Granular task specifically for BMF data (including NTEE codes)
  desc "Imports/Updates core organization data from BMF CSV files (eo*.csv)"
  task import_bmf_data: :environment do
    csv_dir = ENV["CSV_DIR"] || Rails.root.join("data", "csv")

    # Iterate through all BMF files (e.g., eo1.csv, eo2.csv, etc.)
    Dir.glob(File.join(csv_dir, "eo*.csv")).each do |bmf_file_path|
      puts "--- Starting BMF Import from #{File.basename(bmf_file_path)} ---"
      import_bmf(bmf_file_path)
    end

    puts "--- BMF Import/Update Complete ---"
  end

  # NEW: Granular task for the annual extract update
  desc "Updates organization data from the Annual Masterfile Extract CSV"
  task update_annual_extract: :environment do
    csv_dir = ENV["CSV_DIR"] || Rails.root.join("data", "csv")
    annual_extract_file = File.join(csv_dir, "24eoextract990pf.csv")

    puts "--- Starting Annual Extract Update from #{File.basename(annual_extract_file)} ---"
    if File.exist?(annual_extract_file)
      update_from_annual_extract(annual_extract_file)
    else
      puts "WARNING: Annual Extract file not found at #{annual_extract_file}. Skipping."
    end

    puts "--- Annual Extract Update Complete ---"
  end

  # MODIFIED: Master task now just calls the granular tasks
  desc "Imports all BMF and Annual Masterfile CSV data"
  task import_csv_data: :environment do
    Rake::Task["irs:import_bmf_data"].invoke
    Rake::Task["irs:update_annual_extract"].invoke
  end
end
