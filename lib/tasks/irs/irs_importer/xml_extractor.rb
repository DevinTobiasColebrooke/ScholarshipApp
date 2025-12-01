require_relative 'xml_data_transformer'
require_relative 'persistence_updater'

module IrsImporter
class XmlExtractor
  include XmlDataTransformer

  attr_reader :organization

  # Define categories of return types
  FULL_PROCESSING_TYPES = %w[990 990EZ 990PF 990O].freeze
  HEADER_ONLY_TYPES = %w[990T].freeze

  # --- EXPOSE NECESSARY EXTRACTION METHODS (Declared before definition) ---
  public :extract_text

  def initialize(file_path)
    @file_path = file_path
    @file_name = File.basename(file_path)
    @doc = load_xml(@file_path)
    @organization = nil
  end

  # --- PUBLIC HELPER METHODS (Used by Rake tasks) ---

  def extract_return_type
    extract_text("//ReturnTypeCd")
  end

  def setup_organization(ein)
    @organization = Organization.find_by(ein: ein)

    unless @organization
      filer_name = extract_text("//Filer/BusinessName/BusinessNameLine1Txt")

      @organization = Organization.create!(
          ein: ein,
          name: filer_name || "Unknown Organization #{ein}",
      )
      Rails.logger.info "Created new Organization (EIN #{ein}, Name: #{filer_name}) from XML header."
    end

    @organization.present?
  end

  # --- Core Processing Methods (Public API for Rake Tasks) ---

  def process_full_form!
    return false unless @doc

    ein = extract_text("//EIN")
    return false unless ein.present?

    return false unless setup_organization(ein)

    updater = PersistenceUpdater.new(@organization)

    updater.update_organization(extract_organization_fields)
    updater.update_program_services(extract_program_services_data)
    updater.update_grants(extract_grants_paid_data)

    true
  end

  def process_header_only!
    return false unless @doc

    ein = extract_text("//EIN")
    return false unless ein.present?

    return false unless setup_organization(ein)

    updater = PersistenceUpdater.new(@organization)

    updater.update_organization(extract_organization_fields)

    Rails.logger.info "Header-only update complete for EIN #{@organization.ein} (Form: #{extract_return_type})."

    true
  end

  def extract_all_data
    return nil unless @doc

    ein = extract_text("//EIN")
    return nil unless ein.present?

    {
      ein: ein,
      organization_fields: extract_organization_fields,
      program_services: extract_program_services_data,
      grants: extract_grants_paid_data
    }
  end

  # --- Private Helper Methods (Used internally by the class) ---

  private

  def load_xml(file_path)
    Nokogiri::XML(File.open(file_path))
  rescue StandardError => e
    Rails.logger.error "Failed to open/parse XML file #{@file_name}: #{e.message}"
    nil
  end

  # --- Extraction Logic Methods ---

  def extract_organization_fields
    update_fields = {}

    # --- Administrative & Contact (Adding Manager Names) ---
    update_fields[:tax_period_end_dt] = extract_date("//TaxPeriodEndDt")
    update_fields[:formation_yr] = extract_text("//FormationYr")

    # NEW: Manager Names from Part XIV Supplementary Information
    update_fields[:contributing_manager_nm] = extract_text("//ContributingManagerNm")
    update_fields[:shareholder_manager_nm] = extract_text("//ShareholderManagerNm")

    principal_officer = extract_text("//PrincipalOfficerNm")
    principal_officer ||= extract_text("//ReturnHeader/BusinessOfficerGrp/PersonNm")
    update_fields[:principal_officer_nm] = principal_officer

    update_fields[:phone_num] = extract_text("//Filer/PhoneNum")

    filer_address_node = extract_node("//Filer", @doc)
    update_fields[:us_address] = extract_us_address(filer_address_node)

    # --- Mission & Application ---
    update_fields[:activity_or_mission_desc] ||= extract_text("//ActivityOrMissionDesc")
    update_fields[:website_address_txt] ||= extract_text("//WebsiteAddressTxt")
    update_fields[:primary_exempt_purpose_txt] ||= extract_text("//PrimaryExemptPurposeTxt")

    application_info_node = extract_node('//ApplicationSubmissionInfoGrp', @doc)
    if application_info_node
      update_fields[:restrictions_on_awards_txt] = extract_text('RestrictionsOnAwardsTxt', application_info_node)
      update_fields[:submission_deadlines_txt] = extract_text('SubmissionDeadlinesTxt', application_info_node)
      update_fields[:application_materials_txt] = extract_text('FormAndInfoAndMaterialsTxt', application_info_node)
      application_phone = extract_text('RecipientPhoneNum', application_info_node)
      update_fields[:phone_num] ||= application_phone if application_phone.present?

      # NEW: Email Address
      update_fields[:recipient_email_address_txt] = extract_text('RecipientEmailAddressTxt', application_info_node)
    end

    # --- Financial & Qualification (Adding Specific Totals) ---

    update_fields[:cy_grants_and_similar_paid_amt] = extract_decimal("//ContriPaidRevAndExpnssAmt")
    update_fields[:total_grants_paid_xml_amt] = extract_decimal('//TotalGrantOrContriPdDurYrAmt')
    update_fields[:cy_total_revenue_amt] ||= extract_decimal("//TotalRevAndExpnssAmt")

    total_assets = extract_decimal('//TotalAssetsEOYAmt')
    total_liabilities = extract_decimal('//TotalLiabilitiesEOYAmt')

    # Fallback for Total Assets: Check 990T field name (BookValueAssetsEOYAmt)
    total_assets ||= extract_decimal('//BookValueAssetsEOYAmt')

    update_fields[:total_assets_eoy_amt] = total_assets
    update_fields[:total_liabilities_eoy_amt] = total_liabilities

    update_fields[:fmv_assets_eoy_amt] = extract_decimal("//FMVAssetsEOYAmt")
    update_fields[:qualifying_distributions_amt] = extract_decimal("//QualifyingDistributionsAmt")
    update_fields[:grants_to_individuals_ind] = extract_text("//GrantsToIndividualsInd")
    update_fields[:only_contri_preselected_ind] = extract_text("//OnlyContriToPreselectedInd")

    future_grant_group = extract_node('//GrantOrContriApprvForFutGrp', @doc)
    if future_grant_group
      update_fields[:approved_future_grants_xml_amt] = extract_decimal('Amt', future_grant_group)
      update_fields[:total_grant_or_contri_apprv_fut_amt] = extract_decimal('TotalGrantOrContriApprvFutAmt')
      update_fields[:approved_future_grants_purpose] = extract_text('GrantOrContributionPurposeTxt', future_grant_group)
      update_fields[:approved_future_grants_recipient_nm] = extract_text('RecipientBusinessName/BusinessNameLine1Txt', future_grant_group) || extract_text('RecipientPersonNm', future_grant_group)
    end

    # NEW: Charitable Contributions Deduction (Consolidated from 990-T specific fields)
    contribution_amt = extract_decimal('//IRS990T/CharitableContributionsDedAmt')
    update_fields[:charitable_contribution_ded_amt] = contribution_amt

    update_fields.compact!
  end

  def extract_program_services_data
    program_service_data = []
    xpath = "//IRS990PF/*[local-name()='PartIIIStatementOfProgramServiceAccomplishments']/*"

    extract_nodes(xpath).each do |program_node|
      description = extract_text("DescriptionProgramSrvcAccomTxt", program_node)
      description ||= extract_text("MissionDesc", program_node)
      description ||= extract_text("Desc", program_node)

      next unless description.present?

      program_service_data << {
        description_txt: description,
        activity_code: extract_text("ActivityCd", program_node),
        expense_amt: extract_decimal("ExpenseAmt", program_node),
        grant_amt: extract_decimal("GrantAmt", program_node) || extract_decimal("GrantsAndAllocationsAmt", program_node),
        revenue_amt: extract_decimal("RevenueAmt", program_node),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    program_service_data
  end

  def extract_grants_paid_data
    grant_data = []
    grants_xpath = '//IRS990PF/SupplementaryInformationGrp/GrantOrContributionPdDurYrGrp'

    extract_nodes(grants_xpath).each do |grant_node|
      purpose = extract_text('GrantOrContributionPurposeTxt', grant_node)
      amount = extract_decimal('Amt', grant_node)

      recipient_business_name = extract_text('RecipientBusinessName/BusinessNameLine1Txt', grant_node)
      recipient_business_name ||= extract_text('RecipientBusinessName', grant_node)

      recipient_person_nm = extract_text('RecipientPersonNm', grant_node)

      next unless purpose.present? && amount.present? && (recipient_business_name.present? || recipient_person_nm.present?)

      grant_data << {
        purpose_text: purpose,
        amount: amount,
        recipient_person_nm: recipient_person_nm,
        recipient_business_name: recipient_business_name,
        recipient_us_address: extract_us_address(grant_node),
        recipient_foreign_address: extract_text('RecipientForeignAddress', grant_node),
        recipient_relationship_txt: extract_text('RecipientRelationshipTxt', grant_node),
        recipient_foundation_status_txt: extract_text('RecipientFoundationStatusTxt', grant_node),
        created_at: Time.current,
        updated_at: Time.current
      }
    end
    grant_data
  end

  # --- FINAL SCOPING FIX ---
  # These methods must be public so they can be called directly by the Rake tasks
  public :extract_organization_fields, :extract_program_services_data, :extract_grants_paid_data
end
end
