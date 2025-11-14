class Organization < ApplicationRecord
  include PgSearch::Model

  has_neighbors :embedding

  has_many :grants, dependent: :destroy
  has_many :program_services, dependent: :destroy
  has_many :supplemental_infos, dependent: :destroy
  has_one :outreach_contact, dependent: :destroy

  # --- PgSearch Configuration for Comprehensive Scholarship Search ---
  # NOTE: This is kept for the rake backfill task, but is not used by the live scope.
  pg_search_scope :search_scholarships,
    # Search Organization fields directly
    against: [
      :name,
      :activity_or_mission_desc,
      :primary_exempt_purpose_txt
    ],
    # Search associated Grant fields
    associated_against: {
      grants: [:purpose_text]
    },
    # Rely only on tsearch for speed
    using: {
      tsearch: { prefix: true, dictionary: "simple" }
    }
  # -----------------------------------------------------------------

  scope :private_foundation, -> { where(pf_filing_req_cd: "1") }

  scope :included_in_pf_extract, -> { where.not(grnt_indiv_cd: nil) }

  scope :grants_to_individuals, -> { where(grnt_indiv_cd: "Y") }

  scope :approved_future_grants, -> {
    where("grnt_apprv_fut IS NOT NULL AND CAST(grnt_apprv_fut AS numeric) > 0")
  }

  scope :confirmed_grants_to_individuals_xml, -> { where(grants_to_individuals_ind: "x") }

  scope :search_restrictions, ->(query) {
    where("restrictions_on_awards_txt ILIKE :q", q: "%#{query}%")
  }

  scope :active_grantor_indicator, -> { grants_to_individuals.or(approved_future_grants) }

  scope :filter_by_ntee, ->(code) { where("ntee_code LIKE ?", "#{code}%") }

  scope :scholarship_ntee_codes, -> { filter_by_ntee('B82').or(filter_by_ntee('040')) }

  scope :potential_scholarship_grantor, -> {
    private_foundation.scholarship_ntee_codes.active_grantor_indicator
  }

  scope :search_by_ein, ->(ein) { where(ein: ein) }

  scope :has_mission, -> {
    where("activity_or_mission_desc IS NOT NULL OR primary_exempt_purpose_txt IS NOT NULL")
  }

  scope :accepts_unsolicited_requests, -> {
    where.not(only_contri_preselected_ind: 'X')
  }

  scope :only_restricted_grants, -> {
    where(only_contri_preselected_ind: 'X')
  }

  scope :search_mission_text, ->(query) {
    where("activity_or_mission_desc ILIKE :q OR primary_exempt_purpose_txt ILIKE :q", q: "%#{query}%")
  }

  # HIGHLY OPTIMIZED: Now simply searches the pre-calculated boolean column.
  scope :comprehensive_scholarship_search, -> {
    where(is_scholarship_funder: true)
  }

  scope :missing_xml_grant_details, -> {
    comprehensive_scholarship_search
      .grants_to_individuals
      .where.not(id: Grant.select(:organization_id))
  }

  scope :exclude_demographic_keywords, -> {
    exclusion_keywords = [
      'veteran', 'military', 'black', 'african american', 'hispanic', 'latino',
      'asian', 'middle eastern', 'native american', 'african', 'caribbean',
      'men', 'male', 'boy'
    ]

    where_clause = exclusion_keywords.map { |k| "restrictions_on_awards_txt ILIKE '%#{k}%'" }.join(' OR ')
    where.not(where_clause)
  }

  scope :profile_white_woman_26, -> {
    comprehensive_scholarship_search.exclude_demographic_keywords
  }

  def has_grants_in_xml?
    self.grants.exists?
  end

  def to_embeddable_text
    text_content = [
      "Organization Name: #{name}",
      "Private Foundation Filing Requirement: #{pf_filing_req_cd}",
      "NTEE Code: #{ntee_code}",
      "Grants to Individuals Indicator: #{grants_to_individuals_ind}",
      "Is Scholarship Funder: #{is_scholarship_funder}",
      "Approved Future Grants Amount: #{approved_future_grants_xml_amt}",
      "Mission: #{activity_or_mission_desc}"
    ].compact.join("\n")
    "search_document: #{text_content}"
  end
end
