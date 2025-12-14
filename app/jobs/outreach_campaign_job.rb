class OutreachCampaignJob < ApplicationJob
  queue_as :campaigns

  def perform(profile_name, campaign_name, outreach_type = "combined")
    @profile_name = profile_name
    @campaign_name = campaign_name
    @outreach_type = outreach_type

    Rails.logger.info "Starting Campaign '#{@campaign_name}' (Type: #{@outreach_type})"

    sent_count = 0
    mailed_count = 0
    skipped_count = 0

    while next_org = find_next_organization

      contact_email = next_org.org_contact_email.presence
      contact = OutreachContact.find_or_initialize_by(organization: next_org)

      if @outreach_type == "mail_only"
        mark_for_mailing(contact)
        mailed_count += 1
      elsif contact_email.present?
        # HAS EMAIL: Send it
        send_email_outreach(contact, contact_email)
        sent_count += 1
      else
        # NO EMAIL
        if @outreach_type == "email_only"
          # Claim it as processed/skipped for this campaign
          contact.status = :needs_mailing
          contact.campaign_name = @campaign_name
          contact.save!
          skipped_count += 1
        else
          # Combined mode -> Mark for mailing
          mark_for_mailing(contact)
          mailed_count += 1
        end
      end

      # Rate limit only if we actually sent an email
      sleep 2.seconds unless @outreach_type == "mail_only"
    end
    Rails.logger.info "Campaign Complete. Sent: #{sent_count}, Mailed: #{mailed_count}, Skipped: #{skipped_count}"
  end

  private

  def find_next_organization
    eligible_orgs = Organization.public_send(@profile_name)

    # 1. IDs already processed BY THIS SPECIFIC CAMPAIGN run
    #    (So we don't process the same org twice in this loop)
    ids_done_this_campaign = OutreachContact.where(campaign_name: @campaign_name).pluck(:organization_id)

    # 2. IDs that are "Active" in conversation from ANY previous effort
    #    (We generally don't want to interrupt pending/accepted/rejected threads)
    #    Note: We DO want to pick up 'ready_for_email_outreach' and 'needs_mailing'
    ids_active_conversation = OutreachContact.where(status: [ "pending", "accepted", "rejected", "needs_response" ]).pluck(:organization_id)

    ids_to_exclude = (ids_done_this_campaign + ids_active_conversation).uniq

    # Find next org that isn't excluded
    eligible_orgs.where.not(id: ids_to_exclude).order(name: :asc).first
  end

  def mark_for_mailing(contact)
    contact.update!(status: :needs_mailing, campaign_name: @campaign_name)
  end

  def send_email_outreach(contact, email)
    # Update to 'ready' first to ensure data integrity before send
    contact.update!(status: :ready_for_email_outreach, contact_email: email, campaign_name: @campaign_name)
    begin
      mail = OutreachMailer.scholarship_inquiry(contact)
      mail.deliver_now
      contact.update!(status: :pending, last_contact_at: Time.current)
      contact.outreach_logs.create!(log_type: :email_sent, details: "Email sent to #{email}\nSubject: #{mail.subject}")
    rescue => e
      contact.update!(status: :needs_mailing)
      Rails.logger.error "Failed to send: #{e.message}"
    end
  end
end
