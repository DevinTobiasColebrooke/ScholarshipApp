require_relative "irs_importer/xml_extractor"

namespace :irs do
  desc "Lists all 990-T XML files and their EINs for manual inspection"
  task find_990t_files: :environment do
    xml_directory = ENV["XML_DIR"] || Rails.root.join("data", "xml")

    puts "--- Searching for 990-T XML Files in #{xml_directory} ---"
    puts "NOTE: XML parsing can be slow. Please be patient."
    puts "--------------------------------------------------------"

    count = 0

    Dir.glob("#{xml_directory}/*.xml").each do |xml_file|
      extractor = IrsImporter::XmlExtractor.new(xml_file)

      return_type = extractor.extract_return_type
      ein = extractor.extract_text("//EIN")

      next unless return_type == "990T" && ein.present?

      count += 1

      puts "FILE: #{File.basename(xml_file)}"
      puts "  EIN: #{ein}"
      puts "  PATH: #{xml_file}"
      puts "--------------------------------------------------------"
    end

    puts "\n--- Search Complete: Found #{count} Form 990-T XML Files. ---"

    if count.positive?
      puts "To inspect a file, run: cat <PATH_FROM_ABOVE>"
    end
  end
end
