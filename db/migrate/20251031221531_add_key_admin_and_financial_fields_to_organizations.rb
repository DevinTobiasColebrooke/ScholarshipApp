class AddKeyAdminAndFinancialFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :tax_period_end_dt, :date
    add_column :organizations, :formation_yr, :string
    add_column :organizations, :principal_officer_nm, :string
    add_column :organizations, :phone_num, :string
    add_column :organizations, :us_address, :text

    # Balance Sheet Summary Fields (Part X)
    add_column :organizations, :total_assets_eoy_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :total_liabilities_eoy_amt, :decimal, precision: 18, scale: 2
  end
end
