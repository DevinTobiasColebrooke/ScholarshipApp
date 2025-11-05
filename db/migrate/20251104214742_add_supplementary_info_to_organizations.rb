class AddSupplementaryInfoToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :contributing_manager_nm, :string
    add_column :organizations, :shareholder_manager_nm, :string
    add_column :organizations, :recipient_email_address_txt, :string
    add_column :organizations, :total_grant_or_contri_apprv_fut_amt, :decimal, precision: 18, scale: 2
  end
end
