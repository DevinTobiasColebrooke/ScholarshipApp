namespace :org_optimize do
  desc "Calculates and sets the `is_scholarship_funder` flag based on comprehensive criteria (Pure Database Operation)"
  task calculate_scholarship_funder_flag: :environment do
    # Ensure ActiveRecord is available
    Organization

    Rails.logger.level = :info
    start_time = Time.now

    puts "--- Rake Task Initialized and Loading Environment ---"

    # Since the column is dropped/re-added in the migration,
    # we assume all existing values are already FALSE (the default).
    # If the column already existed and was TRUE, we must reset it
    # before we proceed, or the new TRUE updates will be wrong.
    # To be truly safe *in case the migration didn't reset it*,
    # we perform the UPDATE_ALL once more, but without the mandatory print statement
    # that caused the initial confusion.
    # However, since the goal is to eliminate the initial lock, we trust the migration.

    # --- Step 1: Find IDs based on Text Search (PgSearch, the slowest part) ---
    puts "\nPhase 1: Collecting IDs based on 'scholarship' keyword search (This is the longest step, finding matches across Name, Mission, and Grants)..."
    text_start_time = Time.now

    # Uses PgSearch scope defined in app/models/organization.rb
    text_match_ids = Organization.search_scholarships("scholarship").pluck(:id)

    text_duration = (Time.now - text_start_time).round(2)
    puts "   -> Found #{text_match_ids.count} organizations via Text Search. (Took #{text_duration} seconds)"

    # --- Step 2: Find IDs based on NTEE Codes (Fast part) ---
    puts "\nPhase 2: Collecting IDs based on NTEE codes (B82, 040)..."
    # Uses standard scope defined in app/models/organization.rb
    ntee_match_ids = Organization.scholarship_ntee_codes.pluck(:id)
    puts "   -> Found #{ntee_match_ids.count} organizations matching NTEE codes."

    # --- Step 3: Combine and Deduplicate ---
    puts "\nPhase 3: Combining and deduplicating results..."
    all_unique_ids = (text_match_ids + ntee_match_ids).uniq
    total_unique_count = all_unique_ids.count
    puts "   -> Total unique organizations to flag: #{total_unique_count}"

    # --- Step 4: Bulk Update (Setting TRUE) ---
    puts "\nPhase 4: Performing bulk update (setting TRUE flag) on #{total_unique_count} organizations..."

    if total_unique_count > 0
      # Use a direct bulk update based on the array of IDs
      # This operation is very fast because it is only updating a small subset of rows.
      Organization.where(id: all_unique_ids).update_all(is_scholarship_funder: true)

      end_time = Time.now
      duration = (end_time - start_time).round(2)

      puts "\n--- Flag Calculation Complete ---"
      puts "Total matching organizations found and flagged: #{total_unique_count}."
      puts "Total time elapsed: #{duration} seconds."
    else
      puts "\n--- Flag Calculation Complete (No matches found) ---"
      puts "Total time elapsed: #{(Time.now - start_time).round(2)} seconds."
    end
  end
end
