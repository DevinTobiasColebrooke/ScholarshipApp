class OutreachPlannerController < ApplicationController
  PROFILE_PRESETS = {
    'profile_white_woman_26' => 'White Woman / 26'
    # Add more profiles here as they are implemented
  }.freeze

  # Step 1: Name Campaign & Select Preset
  def index
    @profile_presets = PROFILE_PRESETS
  end

  # Step 2: Process selection and redirect to summary
  def create
    campaign_name = params[:campaign_name].presence || "Unnamed Campaign"
    profile_scope_name = params[:profile_scope_name]

    unless PROFILE_PRESETS.key?(profile_scope_name)
      redirect_to outreach_planner_index_path, alert: "Invalid profile selected."
      return
    end

    session[:campaign_name] = campaign_name
    session[:profile_scope_name] = profile_scope_name

    redirect_to outreach_planner_path(id: 'summary')
  end

  # Step 3: Display summary and launch campaign
  def show
    @campaign_name = session[:campaign_name]
    @profile_scope_name = session[:profile_scope_name]

    # If session data is missing, redirect to start over
    unless @campaign_name && @profile_scope_name
      redirect_to outreach_planner_index_path, alert: "Please start a new campaign."
      return
    end

    # 1. Validation and scope access
    unless Organization.respond_to?(@profile_scope_name)
      redirect_to outreach_planner_index_path, alert: "Invalid profile selected."
      return
    end

    # Set the display names
    @profile_display_name = PROFILE_PRESETS[@profile_scope_name]

    # 2. Calculate totals and find the resume point
    eligible_orgs_scope = Organization.public_send(@profile_scope_name)
    @total_org_count = eligible_orgs_scope.count

    # Calculate contacted count
    contacted_org_ids = OutreachContact.pluck(:organization_id)
    @contacted_count = eligible_orgs_scope.where.not(id: contacted_org_ids).count

    # Find the next organization to contact (for display/context)
    @next_organization = eligible_orgs_scope
      .where.not(id: contacted_org_ids)
      .order(name: :asc)
      .first

    # Render the next step (campaign initiation page)
    # render :show is implicit
  end
end
