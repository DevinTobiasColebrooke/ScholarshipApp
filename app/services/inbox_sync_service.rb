require "net/imap"
require "mail"

class InboxSyncService
  IMAP_SERVER = "imap.gmail.com"
  PORT = 993

  # Keywords in the Subject line that indicate a bounce/system message
  BOUNCE_SUBJECTS = [
    "undeliverable",
    "delivery status notification",
    "delivery failure",
    "failure notice",
    "returned mail",
    "mail delivery failed",
    "message not delivered",
    "address not found",
    "recipient not found"
  ].freeze

  # Keywords in the Sender address/name that indicate a system message
  SYSTEM_SENDERS = [
    "mailer-daemon",
    "postmaster",
    "googlemail.com", # Catches mailer-daemon@googlemail.com
    "microsoft-exchange",
    "system administrator"
  ].freeze

  def self.sync
    new.sync_inbox
  end

  def initialize
    @username = Rails.application.credentials.dig(:gmail, :username)
    @password = Rails.application.credentials.dig(:gmail, :app_password)
  end

  def sync_inbox
    Rails.logger.info "📥 Connecting to Gmail IMAP..."

    imap = Net::IMAP.new(IMAP_SERVER, PORT, true)
    imap.login(@username, @password)
    imap.select("INBOX")

    # Search for emails from the last 7 days (both read and unread)
    search_date = (Time.now - 7.days).strftime("%d-%b-%Y")
    email_ids = imap.search([ "SINCE", search_date ])

    if email_ids.empty?
      Rails.logger.info "✓ No emails found in the last 7 days."
      imap.logout
      imap.disconnect
      return
    end

    Rails.logger.info "Scanning #{email_ids.count} emails..."

    email_ids.each do |message_id|
      # Fetch envelope (headers) and body structure
      msg_data = imap.fetch(message_id, "RFC822")[0].attr["RFC822"]
      mail = Mail.read_from_string(msg_data)

      if is_bounce?(mail)
        process_bounce(mail)

        # NEW: Delete the email from Gmail immediately
        imap.store(message_id, "+FLAGS", [ :Deleted ])
        Rails.logger.info "     🗑️ Deleted bounce email from Inbox."
      else
        process_reply(mail)
      end
    end

    # NEW: Permanently remove all messages marked as Deleted
    imap.expunge

    imap.logout
    imap.disconnect
    Rails.logger.info "📥 Inbox Sync Complete."
  rescue => e
    Rails.logger.error "Inbox Sync Error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def is_bounce?(mail)
    subject = mail.subject.to_s.downcase
    from = mail.from&.first.to_s.downcase

    # Check Subject
    return true if BOUNCE_SUBJECTS.any? { |s| subject.include?(s) }

    # Check Sender
    return true if SYSTEM_SENDERS.any? { |s| from.include?(s) }

    false
  end

  def process_bounce(mail)
    # Attempt to extract the failed email from the bounce report
    failed_email = nil

    # 1. Try DSN report part
    if mail.parts.any? { |p| p.content_type =~ /delivery-status/i }
      report = mail.parts.find { |p| p.content_type =~ /delivery-status/i }.body.decoded
      failed_email = report.match(/Final-Recipient: rfc822; (.*)/i)&.captures&.first&.strip
    end

    # 2. Try scanning the body text for common patterns
    # Looks for an email address immediately following "to" or inside < >
    failed_email ||= mail.body.decoded.match(/To:\s*([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,})/i)&.captures&.first
    failed_email ||= mail.body.decoded.match(/<([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,})>/)&.captures&.first

    return unless failed_email

    contact = OutreachContact.find_by("contact_email ILIKE ?", failed_email)

    if contact
      Rails.logger.warn "  🚫 BOUNCE confirmed for #{failed_email}."

      # Remove from Organization (permanent fix)
      contact.organization.update!(org_contact_email: nil)

      # Remove from Campaign
      campaign_name = contact.campaign_name
      contact.destroy

      Rails.logger.info "     Removed contact from '#{campaign_name}' due to bounce."
    else
      # If we can't find a contact, it might be an orphaned email or test
      Rails.logger.info "  - Bounce received for #{failed_email}, but no matching contact found in DB."
    end
  end

  def process_reply(mail)
    from_email = mail.from&.first
    return if from_email.blank?

    contact = OutreachContact.where("contact_email ILIKE ?", from_email).first
    return unless contact

    msg_id = mail.message_id
    if contact.outreach_logs.where("details LIKE ?", "%#{msg_id}%").exists?
      return
    end

    Rails.logger.info "  💌 Reply found! Linked to #{contact.organization.name}"

    body = if mail.text_part
             mail.text_part.decoded
    elsif mail.html_part
             ActionController::Base.helpers.strip_tags(mail.html_part.decoded)
    else
             mail.body.decoded
    end

    clean_body = body.split(/^On .* wrote:$/i).first.strip

    OutreachLog.create!(
      outreach_contact: contact,
      log_type: :response_received,
      details: "Subject: #{mail.subject}\nMessage-ID: #{msg_id}\n\n#{clean_body}"
    )

    unless [ "accepted", "rejected" ].include?(contact.status)
      contact.update!(status: :needs_response)
    end
  end
end
