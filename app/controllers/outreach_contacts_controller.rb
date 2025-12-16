class OutreachContactsController < ApplicationController
  include Pagy::Method

  def index
    if params[:campaign_name].present?
      # DETAIL VIEW: Show specific campaign
      @campaign_name = params[:campaign_name]
      scope = OutreachContact.where(campaign_name: @campaign_name)
                             .includes(:organization, :outreach_logs)
                             .order(updated_at: :desc)

      if params[:status].present?
        scope = scope.where(status: params[:status])
      end

      @pagy, @outreach_contacts = pagy(scope, items: 20)
      render :index_campaign_details
    else
      # LIST VIEW: Show all campaigns
      @campaigns = OutreachContact.group(:campaign_name)
                                  .select("campaign_name,
                                           COUNT(*) as total_count,
                                           COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_count,
                                           COUNT(CASE WHEN status = 'needs_mailing' THEN 1 END) as mailing_count,
                                           MAX(updated_at) as last_activity")
                                  .order("last_activity DESC")
      render :index_campaign_list
    end
  end

  def create
    if params[:profile_name].present?
      campaign_name = params[:campaign_name] || "Unnamed"
      outreach_type = params[:outreach_type] || "combined"
      OutreachCampaignJob.perform_later(params[:profile_name], campaign_name, outreach_type)
      flash.notice = "Campaign started! Emails sending in background."
      redirect_to outreach_contacts_path
    else
      redirect_to outreach_planner_index_path, alert: "Error starting campaign."
    end
  end

  def show
    @contact = OutreachContact.find(params[:id])
    @logs = @contact.outreach_logs.order(created_at: :desc)
    render layout: false
  end

  def update_status
    @contact = OutreachContact.find(params[:id])
    @contact.update(status: params[:status])
    redirect_back fallback_location: outreach_contacts_path(campaign_name: @contact.campaign_name)
  end

  def destroy
    @contact = OutreachContact.find(params[:id])
    @contact.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("#{ActionView::RecordIdentifier.dom_id(@contact)}_row") }
      format.html { redirect_back fallback_location: outreach_contacts_path, notice: "Organization removed." }
    end
  end

  def sync_inbox
    InboxSyncService.sync
    redirect_back fallback_location: outreach_contacts_path, notice: "Inbox synced. Statuses updated based on replies and bounces."
  end

  # NEW: Resume sending emails for an existing campaign
  def resume_campaign
    campaign_name = params[:campaign_name]
    if campaign_name.present?
      # Pass nil for profile_name to indicate "Send Only" mode
      OutreachCampaignJob.perform_later(nil, campaign_name)
      redirect_back fallback_location: outreach_contacts_path, notice: "Sending next batch of emails in background..."
    else
      redirect_back fallback_location: outreach_contacts_path, alert: "Campaign name missing."
    end
  end
end
