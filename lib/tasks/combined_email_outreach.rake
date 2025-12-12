# lib/tasks/combined_email_outreach.rake
require "parallel"
require_relative "email_outreach/helpers"

# This is a helper module to encapsulate the RAG pipeline logic,
# adapted from RagSearchService to work on a pre-defined list of URLs.
module CombinedSearchHelper
  def run_rag_pipeline_on_urls(question:, urls:)
    # 1. Fetch, Chunk Content
    Rails.logger.info "RAG (Combined): Fetching and chunking content from #{urls.count} unique URLs..."
    all_chunks = fetch_and_chunk_content(urls)
    return nil if all_chunks.empty? # Return nil if no context can be built
    Rails.logger.info "RAG (Combined): Generated #{all_chunks.count} text chunks."

    # 2. Perform Vector Similarity Search
    Rails.logger.info "RAG (Combined): Embedding query and text chunks..."
    query_embedding = EmbeddingService.call(question, task: "search_query")
    chunks_with_embeddings = embed_chunks(all_chunks)
    embeddable_chunks = chunks_with_embeddings.reject { |c| c[:embedding].nil? }
    return nil if embeddable_chunks.empty?
    Rails.logger.info "RAG (Combined): Embeddings generated."

    Rails.logger.info "RAG (Combined): Performing semantic ranking..."
    top_chunks = find_top_chunks(query_embedding, embeddable_chunks)
    Rails.logger.info "RAG (Combined): Found top #{top_chunks.count} most relevant chunks."

    # 3. Assemble Dense Context
    Rails.logger.info "RAG (Combined): Assembling final context..."
    context = ""
    top_chunks.each do |top_chunk_data|
      chunk_data = embeddable_chunks[top_chunk_data[:index]]
      context += "Source URL: #{chunk_data[:source_url]}\nContent:\n#{chunk_data[:text]}\n\n---\n\n"
    end
    
    context
  end

  private

  # SELF-CONTAINED VERSION of fetch_page_content to bypass potential loading issues.
  def fetch_page_content(url, browser:)
    browser.go_to(url)
    browser.network.wait_for_idle

    html = browser.body
    doc = Nokogiri::HTML(html)

    # Remove script and style tags to avoid including code in the text
    doc.search('script', 'style').remove

    # Extract all text from the body and clean it up.
    text = doc.text.to_s.gsub(/(\n\s*){3,}/, "\n\n").strip
    
    text
  rescue Ferrum::Error => e
    Rails.logger.error "WebSearchService (self-contained): Ferrum error fetching #{url}: #{e.message}"
    nil
  end

  def fetch_and_chunk_content(urls)
    all_chunks = []
    browser = Ferrum::Browser.new
    urls.each do |url|
      Rails.logger.debug "RAG: Processing #{url}"
      # Call the local, self-contained method instead of the external service
      content = fetch_page_content(url, browser: browser)
      if content.present?
        chunks = content.split(/\n\n+/).map(&:strip).reject(&:empty?)
        chunks.each do |chunk|
          all_chunks << { text: chunk, source_url: url }
        end
      end
    end
    all_chunks
  ensure
    browser&.quit
  end

  def embed_chunks(chunks)
    Parallel.map_with_index(chunks) do |chunk, index|
      begin
        embedding = EmbeddingService.call(chunk[:text], task: "search_document")
        chunk.merge(embedding: embedding)
      rescue EmbeddingService::EmbeddingError => e
        Rails.logger.warn "RAG: Could not embed chunk #{index + 1}: #{e.message}"
        chunk.merge(embedding: nil)
      end
    end
  end

  def find_top_chunks(query_embedding, embeddable_chunks)
    chunk_embeddings = embeddable_chunks.map { |c| c[:embedding] }
    scored_chunks = embeddable_chunks.map.with_index do |chunk, index|
      { index: index, score: cosine_similarity(query_embedding, chunk[:embedding]) }
    end
    scored_chunks.sort_by { |c| -c[:score] }.first(7)
  end

  def dot_product(vec1, vec2); vec1.zip(vec2).map { |x, y| x * y }.sum; end
  def magnitude(vec); Math.sqrt(vec.map { |x| x**2 }.sum); end
  def cosine_similarity(vec1, vec2)
    mag1 = magnitude(vec1)
    mag2 = magnitude(vec2)
    return 0 if mag1 == 0 || mag2 == 0
    dot_product(vec1, vec2) / (mag1 * mag2)
  end
end


namespace :email_outreach do
  desc "Find emails using a COMBINED search from Google and SearXNG. Multi-threaded. Args: [limit, reprocess(true/false)]"
  task :find_emails_with_combined_search, [ :limit, :reprocess ] => :environment do |_, args|
    extend EmailOutreachHelpers
    extend CombinedSearchHelper

    limit = args[:limit]&.to_i unless args[:limit] == "all"
    reprocess = args[:reprocess].to_s == 'true'

    print_header("COMBINED EMAIL SEARCH (Google + SearXNG) FOR '#{EmailOutreachHelpers::CAMPAIGN_NAME}' CAMPAIGN")
    
    if reprocess
      puts "\n-- REPROCESS MODE ENABLED --"
      puts "Deleting all existing outreach contacts for this campaign to start from the beginning..."
      deleted_count = OutreachContact.where(campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME).delete_all
      puts "  -> Deleted #{deleted_count} records."
      puts "Starting from the first organization in the white woman 26 profile scope."
      organizations_query = target_organizations.order(:id)
    else
      puts "\n-- RESUME MODE --"
      puts "Continuing task from where it left off..."
      organizations_query = unprocessed_organizations
    end

    EmailSearchService.reset_daily_limit_flag
    
    # Apply limit after determining the base query
    organizations_query = organizations_query.limit(limit) if limit

    organizations = organizations_query.to_a

    if organizations.empty?
      puts "\n✓ All organizations for this mode have been processed. To start a new cycle, run with the reprocess flag: rake \"email_outreach:find_emails_with_combined_search[all,true]\""
      abort("Exiting.")
    end

    total_orgs_for_this_run = organizations.count
    puts "\n#{total_orgs_for_this_run} organizations to process in this run."
    puts "[MODE: Limited to #{limit} organizations]" if limit
    puts "\nStarting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    print_header("PROCESSING STARTED")

    stats = { found: 0, not_found: 0, errors: 0 }
    processing_stopped = false
    mutex = Mutex.new
    queue = Queue.new
    organizations.each { |org| queue << org }
    EmailOutreachHelpers::NUM_THREADS.times { queue << :done }

    start_time = Time.now
    threads = Array.new(EmailOutreachHelpers::NUM_THREADS) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          # Instantiate the service once per thread
          email_service_instance = EmailSearchService.new(nil)

          loop do
            break if mutex.synchronize { processing_stopped }
            org = queue.pop
            break if org == :done

            begin
              # 1. Build the search query by temporarily setting the organization on the instance
              email_service_instance.instance_variable_set(:@organization, org)
              query = email_service_instance.send(:build_web_search_query)

              # 2. Search both providers
              google_urls = GoogleSearchService.search(query)&.dig("results")&.map { |r| r["url"] } || []
              searxng_urls = WebSearchService.search(query)&.dig("results")&.map { |r| r["url"] } || []
              
              # 3. Combine and de-duplicate URLs
              combined_urls = (google_urls + searxng_urls).uniq
              
              if combined_urls.empty?
                raise "No search results found from either Google or SearXNG."
              end

              # 4. Run the RAG pipeline on the combined URLs
              context = run_rag_pipeline_on_urls(question: query, urls: combined_urls)

              # 5. Extract email from the "super-context"
              if context.present?
                # We need to set the organization on the service instance for the extraction prompt
                email_service_instance.instance_variable_set(:@organization, org)
                email, _ = email_service_instance.send(:extract_email_with_llm, context)
              else
                email = nil
              end

              # 6. Update stats and DB
              mutex.synchronize do
                update_outreach_contact(org: org, email: email)
                stats[email ? :found : :not_found] += 1
                puts "  #{email ? '✓ FOUND' : '○ NOT FOUND'}: #{org.name} #{email ? "(#{email})" : ''}"
              end
            rescue => e
              mutex.synchronize do
                stats[:errors] += 1
                puts "  ✗ ERROR: #{org.name} - #{e.message.truncate(100)}"
              end
            end
          end
        end
      end
    end

    threads.each(&:join)

    elapsed_minutes = ((Time.now - start_time) / 60.0).round(1)
    print_header(processing_stopped ? "TASK STOPPED" : "COMBINED EMAIL SEARCH COMPLETE!")
    puts "Total time: #{elapsed_minutes} minutes"
    puts "\nResults:"
    puts "  ✓ Emails found: #{stats[:found]}"
    puts "  ○ No email (marked for mailing): #{stats[:not_found]}"
    puts "  ✗ Errors: #{stats[:errors]}"
  end

  desc "Re-runs the combined search only for organizations previously marked as 'not_found' (needs_mailing)."
  task :retry_not_found_with_combined_search, [ :limit ] => :environment do |_, args|
    extend EmailOutreachHelpers
    extend CombinedSearchHelper

    limit = args[:limit]&.to_i unless args[:limit] == "all"

    print_header("RETRY 'NOT FOUND' WITH COMBINED SEARCH FOR '#{EmailOutreachHelpers::CAMPAIGN_NAME}' CAMPAIGN")
    EmailSearchService.reset_daily_limit_flag

    # --- TARGETING LOGIC ---
    puts "\nFinding organizations marked as 'needs_mailing' to retry..."
    not_found_org_ids = OutreachContact.where(
      campaign_name: EmailOutreachHelpers::CAMPAIGN_NAME,
      status: 'needs_mailing'
    ).pluck(:organization_id)
    
    organizations_query = Organization.where(id: not_found_org_ids).order(:id)
    
    # Apply limit
    organizations_query = organizations_query.limit(limit) if limit
    organizations = organizations_query.to_a
    
    if organizations.empty?
      abort("\n✓ No organizations found with 'needs_mailing' status to retry.")
    end

    total_orgs_for_this_run = organizations.count
    puts "\n#{total_orgs_for_this_run} organizations to re-process."
    puts "[MODE: Limited to #{limit} organizations]" if limit
    puts "\nStarting in 3 seconds... (Ctrl+C to cancel)"
    sleep 3
    print_header("RE-PROCESSING STARTED")

    # The rest of the logic is identical to the main task
    stats = { found: 0, not_found: 0, errors: 0 }
    processing_stopped = false
    mutex = Mutex.new
    queue = Queue.new
    organizations.each { |org| queue << org }
    EmailOutreachHelpers::NUM_THREADS.times { queue << :done }

    start_time = Time.now
    threads = Array.new(EmailOutreachHelpers::NUM_THREADS) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          email_service_instance = EmailSearchService.new(nil)
          loop do
            break if mutex.synchronize { processing_stopped }
            org = queue.pop
            break if org == :done
            begin
              email_service_instance.instance_variable_set(:@organization, org)
              query = email_service_instance.send(:build_web_search_query)
              google_urls = GoogleSearchService.search(query)&.dig("results")&.map { |r| r["url"] } || []
              searxng_urls = WebSearchService.search(query)&.dig("results")&.map { |r| r["url"] } || []
              combined_urls = (google_urls + searxng_urls).uniq
              raise "No search results found." if combined_urls.empty?
              context = run_rag_pipeline_on_urls(question: query, urls: combined_urls)
              if context.present?
                email_service_instance.instance_variable_set(:@organization, org)
                email, _ = email_service_instance.send(:extract_email_with_llm, context)
              else
                email = nil
              end
              mutex.synchronize do
                update_outreach_contact(org: org, email: email)
                stats[email ? :found : :not_found] += 1
                puts "  #{email ? '✓ FOUND' : '○ NOT FOUND'}: #{org.name} #{email ? "(#{email})" : ''}"
              end
            rescue => e
              mutex.synchronize do
                stats[:errors] += 1
                puts "  ✗ ERROR: #{org.name} - #{e.message.truncate(100)}"
              end
            end
          end
        end
      end
    end
    threads.each(&:join)

    elapsed_minutes = ((Time.now - start_time) / 60.0).round(1)
    print_header(processing_stopped ? "TASK STOPPED" : "RETRY COMPLETE!")
    puts "Total time: #{elapsed_minutes} minutes"
    puts "\nResults:"
    puts "  ✓ Emails found: #{stats[:found]}"
    puts "  ○ No email (marked for mailing): #{stats[:not_found]}"
    puts "  ✗ Errors: #{stats[:errors]}"
  end
end

