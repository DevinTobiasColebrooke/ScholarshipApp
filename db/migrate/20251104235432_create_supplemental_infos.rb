class CreateSupplementalInfos < ActiveRecord::Migration[8.0]
  def change
    create_table :supplemental_infos do |t|
      t.references :organization, null: false, foreign_key: true
      t.string :part_num
      t.string :line_num
      t.text :explanation_txt
      t.decimal :explanation_amt

      t.timestamps
    end
  end
end
