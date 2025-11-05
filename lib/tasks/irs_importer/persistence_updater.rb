module IrsImporter
  class PersistenceUpdater
    def initialize(organization)
      @organization = organization
    end

    # Updates core Organization fields (mission, finance, application)
    def update_organization(fields)
      if fields.any?
        @organization.update!(fields)
        Rails.logger.info "Updated core fields for EIN #{@organization.ein}."
      end
    end

    # Inserts program service records
    def update_program_services(data_array)
      @organization.program_services.delete_all
      if data_array.any?
        ProgramService.insert_all(data_array.map { |d| d.merge(organization_id: @organization.id) })
        Rails.logger.info "Program Services inserted for EIN #{@organization.ein}: #{data_array.count}"
      else
        Rails.logger.info "Program Services found for EIN #{@organization.ein}: 0"
      end
    end

    # Inserts grant records
    def update_grants(data_array)
      @organization.grants.delete_all
      if data_array.any?
        Grant.insert_all(data_array.map { |d| d.merge(organization_id: @organization.id) })
        Rails.logger.info "Grants found for EIN #{@organization.ein}: #{data_array.count}"
      else
        Rails.logger.info "Grants found for EIN #{@organization.ein}: 0"
      end
    end

    def update_supplemental_infos(data_array)
      @organization.supplemental_infos.delete_all
      if data_array.any?
        SupplementalInfo.insert_all(data_array.map { |d| d.merge(organization_id: @organization.id) })
        Rails.logger.info "Supplemental Infos inserted for EIN #{@organization.ein}: #{data_array.count}"
      else
        Rails.logger.info "Supplemental Infos found for EIN #{@organization.ein}: 0"
      end
    end
  end
end
