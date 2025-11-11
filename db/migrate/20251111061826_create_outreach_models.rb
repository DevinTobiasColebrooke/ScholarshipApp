class CreateOutreachModels < ActiveRecord::Migration[8.0]
  def change
    create_table :outreach_contacts do |t|
      t.references :organization, null: false, foreign_key: true, index: { unique: true }

      # Status: :accepted (green), :pending (yellow), :needs_response (blue), :rejected (red)
      # Mapped to a color-coded presentation: green, yellow, blue, red
      t.string :status, null: false, default: 'needs_response'
      t.datetime :last_contact_at
      t.string :contact_email, comment: "The email address actually used for outreach"
      t.text :draft_purpose_vector, comment: "Embedding of the specific profile or draft prompt", limit: 1536

      t.timestamps
    end

    # Table for the history log
    create_table :outreach_logs do |t|
      t.references :outreach_contact, null: false, foreign_key: true

      # Type: :email_sent, :email_received, :status_update, :ai_draft_complete, etc.
      t.string :log_type, null: false
      t.text :details

      t.timestamps
    end

    # Ensure logs can be ordered quickly
    add_index :outreach_logs, :created_at
  end
end
