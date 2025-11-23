require 'parallel'

namespace :embedding do
  desc "Generate embeddings for all organizations (in parallel and resumable)"
  task generate_for_organizations: :environment do
    puts "Starting to generate embeddings for organizations..."

    organizations_to_process = Organization.where(embedding: nil)

    # Get a count for a nice progress message
    total_count = organizations_to_process.count
    puts "Found #{total_count} organizations needing an embedding."

    organizations_to_process.find_in_batches(batch_size: 100) do |organizations_batch|
      puts "Processing a batch of #{organizations_batch.length} (starting with ID #{organizations_batch.first.id})..."
      # Your parallel code is perfect
      Parallel.each(organizations_batch, in_threads: 4) do |org|
        embeddable_text = org.to_embeddable_text

        if embeddable_text.present?
          begin
            # puts "Generating embedding for organization ##{org.id}..." # (Optional: can be noisy)
            embedding = EmbeddingService.call(embeddable_text, task: 'search_document')
            org.update_column(:embedding, embedding)

          rescue EmbeddingService::EmbeddingError => e
            puts "Could not generate embedding for organization ##{org.id}: #{e.message}"
          rescue StandardError => e
            # Catch other unexpected errors so one bad record doesn't stop the batch
            puts "ERROR processing organization ##{org.id}: #{e.message}"
          end
        else
          puts "Skipping organization ##{org.id} due to missing embeddable text."
        end
      end # Parallel.each
    end # find_in_batches

    puts "Finished generating embeddings for organizations."
  end

  desc "Update embeddings for all organizations"
  task update_for_all_organizations: :environment do
    puts "Starting to update embeddings for all organizations..."

    organizations_to_process = Organization.all

    # Get a count for a nice progress message
    total_count = organizations_to_process.count
    puts "Found #{total_count} organizations to update."

    organizations_to_process.find_in_batches(batch_size: 100) do |organizations_batch|
      puts "Processing a batch of #{organizations_batch.length} (starting with ID #{organizations_batch.first.id})..."
      # Your parallel code is perfect
      Parallel.each(organizations_batch, in_threads: 4) do |org|
        embeddable_text = org.to_embeddable_text

        if embeddable_text.present?
          begin
            # puts "Generating embedding for organization ##{org.id}..." # (Optional: can be noisy)
            embedding = EmbeddingService.call(embeddable_text, task: 'search_document')
            org.update_column(:embedding, embedding)

          rescue EmbeddingService::EmbeddingError => e
            puts "Could not generate embedding for organization ##{org.id}: #{e.message}"
          rescue StandardError => e
            # Catch other unexpected errors so one bad record doesn't stop the batch
            puts "ERROR processing organization ##{org.id}: #{e.message}"
          end
        else
          puts "Skipping organization ##{org.id} due to missing embeddable text."
        end
      end # Parallel.each
    end # find_in_batches

    puts "Finished updating embeddings for all organizations."
  end
end
