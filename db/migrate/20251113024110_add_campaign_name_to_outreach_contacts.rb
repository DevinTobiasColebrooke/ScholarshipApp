class AddCampaignNameToOutreachContacts < ActiveRecord::Migration[8.0]
  def change
    add_column :outreach_contacts, :campaign_name, :string
  end
end
