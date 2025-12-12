class RenameRecipientEmailAddressTxtToOrgContactEmailInOrganizations < ActiveRecord::Migration[8.0]
  def change
    rename_column :organizations, :recipient_email_address_txt, :org_contact_email
  end
end
