class CreateWebDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :web_documents do |t|
      t.timestamps
    end
  end
end
