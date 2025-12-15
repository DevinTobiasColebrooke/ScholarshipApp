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
    session[:campaign_name] = campaign_name
    session[:profile_scope_name] = profile_scope_name
    session[:outreach_type] = nil
    redirect_to outreach_planner_path(id: "summary")
  end

  def show
    load_session_data
    return unless @campaign_name

    base_scope = Organization.public_send(@profile_scope_name)

    @total_org_count = base_scope.count

    # UPDATED: Only count emails containing '@'
    @with_email_count = base_scope.where("org_contact_email LIKE '%@%'").count

    @without_email_count = @total_org_count - @with_email_count
  end

  def review
    if params[:outreach_type].present?
      session[:outreach_type] = params[:outreach_type]
    end
    load_session_data
    return unless @campaign_name

    @outreach_type ||= "combined"
    scope = Organization.public_send(@profile_scope_name)

    # UPDATED: Strict filtering
    if @outreach_type == "email_only"
      scope = scope.where("org_contact_email LIKE '%@%'")
    end

    ids_active = OutreachContact.where(status: [ "pending", "accepted", "rejected", "needs_response" ]).pluck(:organization_id)

    scope = scope.where.not(id: ids_active)
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
      redirect_to outreach_planner_index_path, alert: "Session expired."
    end
  end
end
