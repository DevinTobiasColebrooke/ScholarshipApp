class OutreachCampaignJob < ApplicationJob
  queue_as :campaigns

  def perform(profile_name, campaign_name, outreach_type = "combined")
    @profile_name = profile_name
    @campaign_name = campaign_name
    @outreach_type = outreach_type

    # 1. POPULATE PHASE
    # Only populate if a profile is provided.
    # If nil, we assume we are just resuming/processing the existing queue.
    if @profile_name.present?
      populate_campaign_list
    else
      Rails.logger.info "--- Resuming Campaign '#{@campaign_name}' (Sending Only) ---"
    end

    # 2. SENDING PHASE
    process_email_queue
  end

  private

  def populate_campaign_list
    Rails.logger.info "--- Step 1: Populating Campaign List for '#{@campaign_name}' ---"

    # Start with the base profile (e.g., White Woman / 26)
    scope = Organization.public_send(@profile_name)

    # Apply strict "Email Only" filter if selected
    if @outreach_type == "email_only"
      scope = scope.where("org_contact_email LIKE '%@%'")
    end

    # Exclude organizations already in THIS campaign
    existing_org_ids = OutreachContact.where(campaign_name: @campaign_name).select(:organization_id)
    scope = scope.where.not(id: existing_org_ids)

    # Exclude organizations currently active in ANY conversation (Pending/Response/etc)
    active_ids = OutreachContact.where(status: [ "pending", "accepted", "rejected", "needs_response" ]).select(:organization_id)
    scope = scope.where.not(id: active_ids)

    # Bulk create the records so they show up in the UI
    count_added = 0
    scope.find_each do |org|
      has_valid_email = org.org_contact_email.present? && org.org_contact_email.include?("@")

      # Determine status
      status = if has_valid_email
                 :ready_for_email_outreach
      elsif @outreach_type == "email_only"
                 nil # Skip entirely
      else
                 :needs_mailing
      end

      next unless status

      OutreachContact.create(
        organization: org,
        campaign_name: @campaign_name,
        status: status,
        contact_email: (has_valid_email ? org.org_contact_email : nil)
      )
      count_added += 1
    end

    Rails.logger.info "--- Populated #{count_added} new contacts into the tracker ---"
  end

  def process_email_queue
    daily_limit = defined?(GMAIL_CONFIG) ? GMAIL_CONFIG[:daily_limit] : 500
    sleep_time = defined?(GMAIL_CONFIG) ? GMAIL_CONFIG[:rate_limit_seconds] : 3

    Rails.logger.info "--- Step 2: Processing Queue (Limit: #{daily_limit}) ---"

    # Fetch contacts specifically for this campaign that are ready to go
    queue = OutreachContact.where(campaign_name: @campaign_name, status: :ready_for_email_outreach)
                           .order(:id)
                           .limit(daily_limit)

    if queue.empty?
      Rails.logger.info "No emails waiting to be sent for this campaign."
      return
    end

    sent_count = 0

    queue.each do |contact|
      if send_email_outreach(contact)
        sent_count += 1
        sleep sleep_time
      end
    end

    Rails.logger.info "--- Batch Complete. Sent: #{sent_count}/#{daily_limit} ---"
  end

  def send_email_outreach(contact)
    # Double check email validity before attempting
    unless contact.contact_email.present? && contact.contact_email.include?("@")
      contact.update!(status: :needs_mailing)
      return false
    end

    begin
      mail = OutreachMailer.scholarship_inquiry(contact)
      mail.deliver_now

      contact.update!(status: :pending, last_contact_at: Time.current)
      contact.outreach_logs.create!(log_type: :email_sent, details: "Email sent to #{contact.contact_email}\nSubject: #{mail.subject}")
      Rails.logger.info "✓ Sent email to #{contact.organization.name}"
      true
    rescue => e
      # If sending fails, revert to needs_mailing so we don't lose track of them
      contact.update!(status: :needs_mailing)
      Rails.logger.error "Failed to send: #{e.message}"
      false
    end
  end
end
