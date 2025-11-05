class CreateGrants < ActiveRecord::Migration[8.0]
  def change
    create_table :grants do |t|
      t.references :organization, null: false, foreign_key: true
      t.text :purpose_text
      t.decimal :amount
      t.string :recipient_person_nm
      t.string :recipient_business_name
      t.text :recipient_us_address
      t.text :recipient_foreign_address
      t.string :recipient_relationship_txt
      t.string :recipient_foundation_status_txt

      t.timestamps
    end
  end
end
