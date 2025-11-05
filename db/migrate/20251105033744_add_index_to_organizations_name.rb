class AddIndexToOrganizationsName < ActiveRecord::Migration[8.0]
  def change
    add_index :organizations, :name
  end
end
