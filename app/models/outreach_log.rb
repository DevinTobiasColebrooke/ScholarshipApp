# app/models/outreach_log.rb
class OutreachLog < ApplicationRecord
  belongs_to :outreach_contact

  enum :log_type, {
    email_sent: "email_sent",
    response_received: "response_received",
    status_update: "status_update",
    user_note: "user_note",
    ai_draft_requested: "ai_draft_requested",
    ai_draft_complete: "ai_draft_complete",
    ai_response_processed: "ai_response_processed"
  }
end
