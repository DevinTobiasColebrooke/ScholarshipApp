class AddCharitableDeductionToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :charitable_contribution_ded_amt, :decimal, precision: 15, scale: 2
  end
end
