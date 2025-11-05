namespace :irs do
  desc "MASTER TASK: Imports all IRS Organization and Grant data (CSV and XML)"
  task import: [:environment] do
    puts "\n*** STARTING IRS DATA IMPORT (CSV & XML) ***"

    # 1. Load BMF and Annual Extract Data (CSV)
    Rake::Task['irs:import_csv_data'].invoke

    # 2. Load 990T Header Data (Creates Organization and basic fields)
    Rake::Task['irs:import_xml_990t'].invoke

    # 3. Load FULL 990 XML Data for Missions, Website, and Grants
    Rake::Task['irs:import_xml_data'].invoke

    puts "\n*** All Data Import Complete. Vectorization is skipped. ***"
  end
end
