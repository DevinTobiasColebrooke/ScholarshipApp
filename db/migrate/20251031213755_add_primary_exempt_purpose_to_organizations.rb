class AddPrimaryExemptPurposeToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :primary_exempt_purpose_txt, :text
    add_column :organizations, :cy_contributions_grants_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :cy_program_service_revenue_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :cy_total_revenue_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :cy_grants_and_similar_paid_amt, :decimal, precision: 18, scale: 2
    add_column :organizations, :total_program_service_expenses_amt, :decimal, precision: 18, scale: 2
  end
end
