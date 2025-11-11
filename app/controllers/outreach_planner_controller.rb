class OutreachPlannerController < ApplicationController
  # The page where the user selects the profile
  def index
    @available_profiles = {
      'profile_white_woman_26' => 'White Woman / 26'
      # Add more profiles here as they are implemented
    }
  end

  # The action that displays the predicted total count and the "Start" button
  def show
    profile_scope_name = params[:profile_name]

    # 1. Validation and scope access
    unless Organization.respond_to?(profile_scope_name)
      redirect_to outreach_planner_index_path, alert: "Invalid profile selected."
      return
    end

    # Set the display names
    @profile_name = profile_scope_name
    @profile_display_name = { 'profile_white_woman_26' => 'White Woman / 26'}[@profile_name]

    # 2. Calculate totals and find the resume point
    eligible_orgs_scope = Organization.public_send(@profile_name)
    @total_org_count = eligible_orgs_scope.count

    # Calculate contacted count
    contacted_org_ids = OutreachContact.pluck(:organization_id)
    @contacted_count = eligible_orgs_scope.where(id: contacted_org_ids).count

    # Find the next organization to contact (for display/context)
    @next_organization = eligible_orgs_scope
      .where.not(id: contacted_org_ids)
      .order(name: :asc)
      .first

    # Render the next step (campaign initiation page)
    render :show
  end
end
