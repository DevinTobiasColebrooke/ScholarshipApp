class OutreachCampaignJob < ApplicationJob
  queue_as :campaigns

  def perform(profile_name, campaign_name, outreach_type = "combined")
    @profile_name = profile_name
    @campaign_name = campaign_name
    @outreach_type = outreach_type

    daily_limit = defined?(GMAIL_CONFIG) ? GMAIL_CONFIG[:daily_limit] : 50

    Rails.logger.info "Starting Campaign '#{@campaign_name}' (Type: #{@outreach_type})"
    Rails.logger.info "⚠️ Enforcing Daily Limit: #{daily_limit} emails max per run."

    sent_count = 0
    mailed_count = 0
    skipped_count = 0

    while next_org = find_next_organization
      if sent_count >= daily_limit
        Rails.logger.warn "🛑 DAILY LIMIT REACHED (#{sent_count} emails sent). Stopping job."
        break
      end

      # UPDATED: Strict check for valid email format
      raw_email = next_org.org_contact_email.presence
      contact_email = (raw_email && raw_email.include?("@")) ? raw_email : nil

      contact = OutreachContact.find_or_initialize_by(organization: next_org)

      if @outreach_type == "mail_only"
        mark_for_mailing(contact)
        mailed_count += 1
      elsif contact_email.present?
        # HAS VALID EMAIL (@): Send it
        if send_email_outreach(contact, contact_email)
          sent_count += 1
          sleep 5.seconds
        end
      else
        # NO VALID EMAIL (nil or website url)
        if @outreach_type == "email_only"
          contact.status = :needs_mailing
          contact.campaign_name = @campaign_name
          contact.save!
          skipped_count += 1
        else
          mark_for_mailing(contact)
          mailed_count += 1
        end
      end
    end
    Rails.logger.info "Campaign Complete. Sent: #{sent_count}/#{daily_limit}, Mailed: #{mailed_count}, Skipped: #{skipped_count}"
  end

  private

  def find_next_organization
    eligible_orgs = Organization.public_send(@profile_name)
    ids_done_this_campaign = OutreachContact.where(campaign_name: @campaign_name).pluck(:organization_id)
    ids_active_conversation = OutreachContact.where(status: [ "pending", "accepted", "rejected", "needs_response" ]).pluck(:organization_id)
    ids_to_exclude = (ids_done_this_campaign + ids_active_conversation).uniq

    eligible_orgs.where.not(id: ids_to_exclude).order(name: :asc).first
  end

  def mark_for_mailing(contact)
    contact.update!(status: :needs_mailing, campaign_name: @campaign_name)
  end

  def send_email_outreach(contact, email)
    contact.update!(status: :ready_for_email_outreach, contact_email: email, campaign_name: @campaign_name)
    begin
      mail = OutreachMailer.scholarship_inquiry(contact)
      mail.deliver_now
      contact.update!(status: :pending, last_contact_at: Time.current)
      contact.outreach_logs.create!(log_type: :email_sent, details: "Email sent to #{email}\nSubject: #{mail.subject}")
      Rails.logger.info "✓ Sent email to #{contact.organization.name}"
      true
    rescue => e
      contact.update!(status: :needs_mailing)
      Rails.logger.error "Failed to send: #{e.message}"
      false
    end
  end
end
