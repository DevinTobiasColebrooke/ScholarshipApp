class AddApplicationMaterialsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :application_materials_txt, :string, comment: "Part XIV Line 2b"
  end
end
