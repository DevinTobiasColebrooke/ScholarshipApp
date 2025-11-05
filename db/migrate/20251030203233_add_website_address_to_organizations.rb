class AddWebsiteAddressToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :website_address_txt, :string
  end
end
