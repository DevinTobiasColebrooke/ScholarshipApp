class AddIndexToPreselectedIndicator < ActiveRecord::Migration[8.0]
  def change
    add_index :organizations, :only_contri_preselected_ind
  end
end
