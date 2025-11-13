class OutreachCampaignJob < ApplicationJob
  queue_as :campaigns

  # This job handles the persistent, resumable loop over the target list.
  def perform(profile_name, campaign_name = "Unnamed Campaign")
    @profile_name = profile_name
    @campaign_name = campaign_name

    Rails.logger.info "Starting Outreach Campaign '#{@campaign_name}' for Profile: #{@profile_name}"

    # Loop as long as there are organizations to contact
    while next_org = find_next_organization_to_contact

      # 1. Create the outreach contact (this is the resume point)
      contact = OutreachContact.create!(
        organization: next_org,
        status: :needs_response,
        contact_email: next_org.recipient_email_address_txt.presence,
        campaign_name: @campaign_name # Store the campaign name
      )

      Rails.logger.info "Initiated outreach for: #{next_org.name} (ID: #{contact.id}) in campaign '#{@campaign_name}'. Next in queue."

      # 2. Trigger the AI Drafting Job (which is the next, separate step)
      contact.draft_initial_email(@profile_name)

      # Pause before initiating the next contact to simulate a safe, batched process
      sleep 10.seconds
    end

    Rails.logger.info "Outreach Campaign '#{@campaign_name}' for #{@profile_name} finished. All organizations processed."
  end

  private

  # Finds the next eligible organization based on the selected profile
  # that has *not* yet been given an OutreachContact record.
  def find_next_organization_to_contact
    # Use the scope from the Organization model
    eligible_orgs = Organization.public_send(@profile_name)

    # Find all IDs that have an OutreachContact already
    contacted_org_ids = OutreachContact.pluck(:organization_id)

    # Filter the eligible orgs to those NOT in the contacted list
    next_org = eligible_orgs
      .where.not(id: contacted_org_ids)
      .order(name: :asc) # Stable sort key for resumption (resume where we left off alphabetically)
      .first

    next_org
  end
end
