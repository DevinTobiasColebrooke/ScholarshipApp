class OutreachContactsController < ApplicationController
  include Pagy::Method

  def index
    # Apply filter by status if present
    @status_filter = params[:status]
    scope = OutreachContact.includes(:organization, :outreach_logs).order(updated_at: :desc)

    if @status_filter.present? && OutreachContact.statuses.key?(@status_filter)
      scope = scope.where(status: @status_filter)
    end

    @pagy, @outreach_contacts = pagy(scope, items: 20)

    # NEW: Handle the initiation POST request from the Planner
    # This is the "Start Outreach" button that triggers the campaign job.
    if request.post? && params[:profile_name].present?
      OutreachCampaignJob.perform_later(params[:profile_name])
      flash.notice = "Outreach campaign for #{params[:profile_name].humanize} started in the background! Watch the table populate."
      # Clear the post status and redirect to the list view
      redirect_to outreach_contacts_path
      return
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  # Action to view the logs for a single contact (loaded into a turbo_streamed dropdown row)
  def show
    @contact = OutreachContact.find(params[:id])
    @logs = @contact.outreach_logs.order(created_at: :desc)

    render layout: false
  end

  # NOTE: The create action is implicitly handled by the job now, so no explicit
  # create action is needed here unless manual creation is desired.
end
