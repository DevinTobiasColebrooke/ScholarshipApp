class OutreachPlannerController < ApplicationController
  PROFILE_PRESETS = {
    "profile_white_woman_26" => "White Woman / 26"
    # Add more profiles here as they are implemented
  }.freeze

  # Step 1: Name Campaign & Select Preset
  def index
    @profile_presets = PROFILE_PRESETS
  end

  # Step 2: Save to Session
  def create
    campaign_name = params[:campaign_name].presence || "Unnamed Campaign"
    profile_scope_name = params[:profile_scope_name]
    outreach_type = params[:outreach_type] || "combined"

    unless PROFILE_PRESETS.key?(profile_scope_name)
      redirect_to outreach_planner_index_path, alert: "Invalid profile selected."
      return
    end

    session[:campaign_name] = campaign_name
    session[:profile_scope_name] = profile_scope_name
    session[:outreach_type] = outreach_type

    redirect_to outreach_planner_path(id: "summary")
  end

  def show
    load_session_data
    return unless @campaign_name

    base_scope = Organization.public_send(@profile_scope_name)

    # Calculate stats based on Outreach Type
    case @outreach_type
    when "email_only"
      @total_target_count = base_scope.where.not(org_contact_email: nil).count
      @orgs_with_email_count = @total_target_count
      @orgs_skipped_count = base_scope.where(org_contact_email: nil).count
    when "mail_only"
      @total_target_count = base_scope.count
      @orgs_with_email_count = 0
      @orgs_needs_mail_count = @total_target_count
    else # combined
      @total_target_count = base_scope.count
      @orgs_with_email_count = base_scope.where.not(org_contact_email: nil).count
      @orgs_needs_mail_count = @total_target_count - @orgs_with_email_count
    end
  end

  def review
    load_session_data
    return unless @campaign_name

    scope = Organization.public_send(@profile_scope_name)

    # Filter 1: Outreach Type (Email Only logic)
    if @outreach_type == "email_only"
      scope = scope.where.not(org_contact_email: nil)
    end

    # Filter 2: Exclude Active Conversations (Pending/Accepted/Rejected)
    # We WANT to show 'ready_for_email_outreach' and 'needs_mailing' as they will be processed.
    ids_active_conversation = OutreachContact.where(status: [ "pending", "accepted", "rejected", "needs_response" ]).pluck(:organization_id)

    scope = scope.where.not(id: ids_active_conversation)
                 .includes(:outreach_contact)
                 .order(name: :asc)

    @pagy, @campaign_organizations = pagy(scope, items: 50)
    @total_recipients = @pagy.count
  end

  private

  def load_session_data
    @campaign_name = session[:campaign_name]
    @profile_scope_name = session[:profile_scope_name]
    @outreach_type = session[:outreach_type]
    @profile_display_name = PROFILE_PRESETS[@profile_scope_name]

    unless @campaign_name && @profile_scope_name
      redirect_to outreach_planner_index_path, alert: "Session expired. Please start over."
    end
  end
end
