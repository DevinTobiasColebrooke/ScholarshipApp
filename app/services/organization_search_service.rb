class OrganizationSearchService
  attr_reader :params

  def initialize(params = {})
    @params = params.deep_symbolize_keys
  end

  def call
    organizations = Organization.all

    if params[:semantic_query].present?
      return apply_semantic_search(organizations)
    end

    if params[:preset_scholarship_search] == "1"
      organizations = organizations.comprehensive_scholarship_search
    end

    if params[:profile_white_woman_26] == "1"
      organizations = organizations.profile_white_woman_26
    end

    organizations = apply_structured_filters(organizations)
    organizations = apply_identifier_search(organizations)
    organizations = apply_text_search(organizations)
    organizations = apply_program_service_search(organizations)
    organizations = apply_grant_purpose_search(organizations)
    organizations = apply_restrictions_search(organizations)

    organizations.order(name: :asc)
  end

  private

  def apply_semantic_search(organizations)
    embedding = EmbeddingService.call(params[:semantic_query], task: "search_query")
    organizations.nearest_neighbors(:embedding, embedding, distance: "euclidean").first(100)
  end

  def apply_identifier_search(organizations)
    if params[:ein_query].present?
      organizations = organizations.search_by_ein(params[:ein_query])
    end

    if params[:has_mission_filter] == "1"
      organizations = organizations.has_mission
    end

    organizations
  end

  def apply_structured_filters(organizations)
    if params[:show_restricted_only] == "1"
        return organizations.only_restricted_grants
    end

    if params[:scholarship_filter] == "1" && params[:preset_scholarship_search] != "1" && params[:profile_white_woman_26] != "1"
      organizations = organizations.potential_scholarship_grantor
    end

    if params[:active_grantor_filter] == "1"
      organizations = organizations.active_grantor_indicator
    end

    if params[:confirmed_grants_to_individuals_xml] == "1"
      organizations = organizations.confirmed_grants_to_individuals_xml
    end

    if params[:ntee_filter].present?
      organizations = organizations.filter_by_ntee(params[:ntee_filter])
    end

    organizations
  end

  def apply_text_search(organizations)
    if params[:mission_query].present?
      organizations = organizations.search_mission_text(params[:mission_query])
    end
    organizations
  end

  def apply_grant_purpose_search(organizations)
    if params[:grant_purpose_query].present?
      organizations = organizations.joins(:grants)
                                   .merge(Grant.search_purpose_text(params[:grant_purpose_query]))
                                   .distinct
    end
    organizations
  end

  def apply_program_service_search(organizations)
    if params[:program_service_query].present?
      organizations = organizations.joins(:program_services)
                                   .merge(ProgramService.search_description_text(params[:program_service_query]))
                                   .distinct
    end
    organizations
  end

  def apply_restrictions_search(organizations)
    if params[:restrictions_query].present?
      organizations = organizations.search_restrictions(params[:restrictions_query])
    end
    organizations
  end
end
