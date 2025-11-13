class AddEmbeddingToOrganizations < ActiveRecord::Migration[8.0]
  def change
    add_column :organizations, :embedding, :vector, limit: 768
    add_index :organizations, :embedding, using: :ivfflat, opclass: :vector_l2_ops
  end
end
