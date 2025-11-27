class AddColumnsToWebDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :web_documents, :url, :string
    add_column :web_documents, :content, :text
    add_column :web_documents, :embedding, :vector, limit: 768
  end
end
