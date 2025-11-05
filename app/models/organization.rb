class Organization < ApplicationRecord
  include PgSearch::Model

  has_many :grants, dependent: :destroy
  has_many :program_services, dependent: :destroy
  has_many :supplemental_infos, dependent: :destroy

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

  scope :min_qualifying_distributions, ->(amount) {
    where("qualifying_distributions_amt >= ?", amount.to_i)
  }

  scope :min_fmv_assets, ->(amount) {
    where("fmv_assets_eoy_amt >= ?", amount.to_i)
  }

  scope :active_grantor_indicator, -> { grants_to_individuals.or(approved_future_grants) }

  scope :filter_by_ntee, ->(code) { where("ntee_code LIKE ?", "#{code}%") }

  scope :scholarship_ntee_codes, -> { filter_by_ntee('B82').or(filter_by_ntee('040')) }

  scope :potential_scholarship_grantor, -> {
    private_foundation.scholarship_ntee_codes.active_grantor_indicator
  }

  scope :search_by_ein, ->(ein) {
    where("ein LIKE ?", "#{ein}%")
  }

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

  def has_grants_in_xml?
    self.grants.exists?
  end
end
