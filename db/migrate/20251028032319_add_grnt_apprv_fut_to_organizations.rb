class AddGrntApprvFutToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :grnt_apprv_fut, :string
  end
end
