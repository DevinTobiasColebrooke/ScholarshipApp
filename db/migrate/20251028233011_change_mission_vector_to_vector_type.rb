class ChangeMissionVectorToVectorType < ActiveRecord::Migration[8.0]
  def change
    # Step 1: Remove the existing 'text' column
    # Use remove_column with the type for proper down migration handling
    remove_column :organizations, :mission_vector, :text

    # Step 2: Add the new 'vector' column with the correct size (dimension)
    # The 'vector' type is made available by the pgvector gem
    add_column :organizations, :mission_vector, :vector, limit: 1536
  end
end
