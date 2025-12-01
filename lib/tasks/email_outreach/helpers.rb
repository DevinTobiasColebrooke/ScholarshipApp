# Helper module to encapsulate shared logic for the email_outreach rake tasks.
# This promotes DRY principles by centralizing configuration, queries, and utility functions.
module EmailOutreachHelpers
  # --- Configuration ---
  CAMPAIGN_NAME = "White Woman/26 Profile".freeze
  NUM_THREADS = 3
  TEST_MULTIPLE_DELAY = 0.5

  # --- UI & Logging Helpers ---

  def print_header(title)
    puts "=" * 60
    puts title.upcase
    puts "=" * 60
  end

  def setup_verbose_logger
    Rails.logger = Logger.new($stdout)
    Rails.logger.level = :debug
    Rails.logger.formatter = proc do |severity, datetime, _progname, msg|
      "#{datetime.strftime('%H:%M:%S')} #{severity}: #{msg}\n"
    end
  end

  def handle_generic_error(e)
    puts "\n" + "!" * 60
    puts "ERROR"
    puts "!" * 60
    puts "Error class: #{e.class}"
    puts "Error message: #{e.message}"
    puts "\nPlease check:"
    puts "  1. Is GEMINI_API_KEY set in your environment?"
    puts "  2. Is the API key valid?"
    puts "  3. Do you have internet connectivity?"
  end

  def handle_service_unavailable(e = nil)
    puts "\n" + "!" * 60
    puts "SERVICE TEMPORARILY UNAVAILABLE"
    puts "!" * 60
    puts "The local LLM server is temporarily unavailable or experiencing issues."
    puts "Please ensure your local LLM server is running and try again."
    puts "Error: #{e.message}" if e
  end

  # --- Data Query Helpers ---

  def target_organizations
    Organization.profile_white_woman_26
  end

  def processed_organization_ids
    OutreachContact.where(campaign_name: CAMPAIGN_NAME).pluck(:organization_id)
  end

  def unprocessed_organizations(limit: nil)
    query = target_organizations.where.not(id: processed_organization_ids)
    query = query.limit(limit) if limit
    query.to_a
  end

  # --- Core Logic Helpers ---

  def find_email_for_org(org)
    start_time = Time.now
    email = EmailSearchService.new(org).find_email
    elapsed = (Time.now - start_time).round(2)
    [email, elapsed]
  end

  def update_outreach_contact(org:, email:)
    if email
      org.update(org_contact_email: email)
      OutreachContact.find_or_create_by(organization: org, campaign_name: CAMPAIGN_NAME) do |contact|
        contact.status = 'ready_for_email_outreach'
        contact.contact_email = email
      end
    else
      OutreachContact.find_or_create_by(organization: org, campaign_name: CAMPAIGN_NAME) do |contact|
        contact.status = 'needs_mailing'
      end
    end
  end
end
