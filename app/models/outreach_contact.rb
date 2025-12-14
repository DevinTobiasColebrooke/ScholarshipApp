class OutreachContact < ApplicationRecord
  belongs_to :organization
  has_many :outreach_logs, dependent: :destroy

  enum :status, {
    ready_for_email_outreach: "ready_for_email_outreach", # Email found, ready for bulk sending
    needs_mailing: "needs_mailing",                       # Email not found, needs physical mail
    pending: "pending",                                   # Email sent, waiting for reply
    needs_response: "needs_response",                     # Response received, needs user action
    accepted: "accepted",                                 # Positive response
    rejected: "rejected"                                  # Negative response
  }

  validates :status, inclusion: { in: statuses.keys }

  # Automatically retrieve the best available email from the organization record
  def inferred_contact_email
    organization.org_contact_email.presence
  end

  # Helper for view colors
  def status_color_class
    case status
    when "accepted" then "bg-green-100 border-green-500"
    when "pending" then "bg-yellow-100 border-yellow-500"
    when "needs_response" then "bg-blue-100 border-blue-500"
    when "ready_for_email_outreach" then "bg-purple-100 border-purple-500"
    when "needs_mailing" then "bg-gray-100 border-gray-500"
    when "rejected" then "bg-red-100 border-red-500"
    else "bg-gray-100 border-gray-500"
    end
  end
end
