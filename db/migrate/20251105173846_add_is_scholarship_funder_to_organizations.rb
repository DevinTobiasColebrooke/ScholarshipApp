class AddIsScholarshipFunderToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :is_scholarship_funder, :boolean, default: false
    add_index :organizations, :is_scholarship_funder
  end
end
