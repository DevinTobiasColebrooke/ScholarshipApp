class AddUnsolicitedRequestIndicatorToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :only_contri_preselected_ind, :string, comment: "Part XIV Line 2, X if foundation only makes contributions to preselected charities."
  end
end
