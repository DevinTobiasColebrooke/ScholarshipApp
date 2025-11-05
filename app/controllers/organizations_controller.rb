class OrganizationsController < ApplicationController
  def index
    search_service = OrganizationSearchService.new(organization_search_params)
    full_scope = search_service.call

    search_params_present = params.except(:controller, :action, :page).compact_blank.present?

    if !search_params_present && params[:page].blank?
      @pagy, @organizations = pagy(full_scope.limit(21), items: 20)
      @total_count_display = TOTAL_ORGANIZATION_COUNT
    else
      @pagy, @organizations = pagy(full_scope, items: 20)
      @total_count_display = @pagy.count
    end

    respond_to do |format|
      format.html
      format.turbo_stream { render :index }
    end
  end

  def show
    # FIX: Eager load the new supplemental_infos association to prevent N+1 queries.
    @organization = Organization.includes(:supplemental_infos).find(params[:id])

    begin
      # IMPORTANT: If you want grants to link to recipients, ensure you've done the name matching logic in Grant model.
      all_grants = @organization.grants.order(amount: :desc).limit(100)

      # Split grants:
      # 1. Organization Grants: prioritize if recipient_business_name is present.
      @organization_grants = all_grants.select { |g| g.recipient_business_name.present? }

      # 2. Individual Grants: those remaining where recipient_person_nm is present.
      remaining_grants = all_grants - @organization_grants
      @individual_grants = remaining_grants.select { |g| g.recipient_person_nm.present? }

      @total_grants_count = @organization_grants.count + @individual_grants.count

      @program_services = @organization.program_services.order(grant_amt: :desc)

      # FIX: N+1 Prevention Logic (Recipient Map)
      recipient_names = @organization_grants.filter_map do |g|
        g.recipient_business_name.to_s.upcase.strip.presence
      end.uniq

      @recipient_org_map = Organization.where("UPPER(name) IN (?)", recipient_names)
                                       .index_by { |o| o.name.upcase.strip }

    rescue => e
      # Log the error for debugging, but prevent application crash
      Rails.logger.error "ERROR: Failed to load associated records for organization #{@organization.id}: #{e.message}"
      @organization_grants = []
      @individual_grants = []
      @total_grants_count = 0
      @program_services = []
      @recipient_org_map = {}
    end
  end

  def potential_scholarship_grantors
    params[:scholarship_filter] = "1"
    search_service = OrganizationSearchService.new(organization_search_params)
    full_scope = search_service.call

    full_scope = full_scope.includes(:grants)

    # Let Pagy handle the count here (will be slow but stable)
    @pagy, @organizations = pagy(full_scope, items: 20)
    @total_count_display = @pagy.count

    render :index
  end

  private

  def organization_search_params
    permitted_params = params.permit(
      :ein_query,
      :has_mission_filter,
      :scholarship_filter,
      :confirmed_grants_to_individuals_xml,
      :page,
      :active_grantor_filter,
      :show_restricted_only,
      :ntee_filter,
      :preset_scholarship_search
    )
    .to_h.deep_symbolize_keys

    permitted_params.each do |key, value|
      if value == "0" || value.to_s.empty?
        permitted_params[key] = nil
      end
    end

    permitted_params
  end
end
