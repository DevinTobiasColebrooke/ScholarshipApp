class AddXmlSummaryGrantsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :total_grants_paid_xml_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :approved_future_grants_xml_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :approved_future_grants_purpose, :text
    add_column :organizations, :approved_future_grants_recipient_nm, :string
  end
end
