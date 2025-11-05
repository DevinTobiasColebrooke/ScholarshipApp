class AddGrantQualifierFieldsToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :grants_to_individuals_ind, :string, comment: 'Part IV Line 22, Schedule I confirmation'
    add_column :organizations, :restrictions_on_awards_txt, :text, comment: 'Part XIV Line 2d'
    add_column :organizations, :submission_deadlines_txt, :string, comment: 'Part XIV Line 2c'

    add_column :organizations, :fmv_assets_eoy_amt, :decimal, precision: 18, scale: 2, comment: 'FMVAssetsEOYAmt (990PF Index I)'
    add_column :organizations, :qualifying_distributions_amt, :decimal, precision: 18, scale: 2, comment: 'Part XI Line 4'
  end
end
