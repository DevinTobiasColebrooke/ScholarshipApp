class ResetIsScholarshipFunderColumn < ActiveRecord::Migration[8.0]
  def change
    def up
      # This migration explicitly performs the reset via schema manipulation.
      # It attempts to DROP the column and then ADD it back, including the default value and index.

      # NOTE: Dropping and re-adding may temporarily lose the index,
      # but the index is recreated immediately afterward.

      # 1. Remove the index first
      remove_index :organizations, :is_scholarship_funder, if_exists: true

      # 2. Drop the column
      remove_column :organizations, :is_scholarship_funder, if_exists: true

      # 3. Add the column back with the necessary default and index
      add_column :organizations, :is_scholarship_funder, :boolean, default: false
      add_index :organizations, :is_scholarship_funder
    end

    def down
      # To undo, we just remove the column
      remove_index :organizations, :is_scholarship_funder, if_exists: true
      remove_column :organizations, :is_scholarship_funder, if_exists: true
    end
  end
end
