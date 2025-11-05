class CreateOrganizations < ActiveRecord::Migration[8.0]
  def change
    create_table :organizations do |t|
      t.string :ein
      t.string :name
      t.string :pf_filing_req_cd
      t.string :grnt_indiv_cd
      t.string :ntee_code
      t.text :activity_or_mission_desc
      t.text :mission_vector, limit: 1536

      t.timestamps
    end
    add_index :organizations, :ein, unique: true
  end
end
