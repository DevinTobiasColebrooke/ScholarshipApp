class FixUniqueIndexOnOutreachContacts < ActiveRecord::Migration[8.0]
  def change
    # Remove the old unique index on just organization_id
    remove_index :outreach_contacts, name: "index_outreach_contacts_on_organization_id"

    # Add a new unique index on both organization_id and campaign_name
    # This allows an organization to be part of multiple campaigns.
    add_index :outreach_contacts, [ :organization_id, :campaign_name ], unique: true, name: "index_outreach_contacts_on_org_id_and_campaign_name"
  end
end
