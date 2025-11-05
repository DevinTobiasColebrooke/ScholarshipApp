class CreateProgramServices < ActiveRecord::Migration[8.0]
  def change
    create_table :program_services do |t|
      t.references :organization, null: false, foreign_key: true
      t.text :description_txt, comment: 'DescriptionProgramSrvcAccomTxt'
      t.string :activity_code, comment: 'ActivityCd'
      t.decimal :expense_amt, precision: 18, scale: 2, comment: 'ExpenseAmt'
      t.decimal :grant_amt, precision: 18, scale: 2, comment: 'GrantAmt'
      t.decimal :revenue_amt, precision: 18, scale: 2, comment: 'RevenueAmt'

      t.timestamps
    end
  end
end
