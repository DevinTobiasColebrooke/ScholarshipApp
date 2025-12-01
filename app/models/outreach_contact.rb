class OutreachContact < ApplicationRecord
  belongs_to :organization
  has_many :outreach_logs, dependent: :destroy

  enum :status, {
    ready_for_email_outreach: 'ready_for_email_outreach', # New: Email found, ready for initial outreach
    needs_mailing: 'needs_mailing',                       # New: Email not found, needs physical mail
    needs_response: 'needs_response',                     # Blue: AI read email, needs user intervention to respond
    pending: 'pending',                                   # Yellow: Email sent, waiting for reply
    accepted: 'accepted',                                 # Green: Accepted (positive response)
    rejected: 'rejected'                                  # Red: Denied (negative response)
  }

  validates :status, inclusion: { in: statuses.keys }

  # Automatically retrieve the best available email from the organization record
  def inferred_contact_email
    organization.org_contact_email.presence
  end

  # Triggers the AI Draft Job
  def draft_initial_email(profile_name)
    AiEmailDraftingJob.perform_later(self.id, profile_name)

    self.outreach_logs.create(
      log_type: 'ai_draft_requested',
      details: "Requested AI draft for profile: #{profile_name}"
    )
  end

  # Helper for view colors
  def status_color_class
    case status
    when 'accepted' then 'bg-green-100 border-green-500'
    when 'pending' then 'bg-yellow-100 border-yellow-500'
    when 'needs_response' then 'bg-blue-100 border-blue-500'
    when 'ready_for_email_outreach' then 'bg-purple-100 border-purple-500'
    when 'needs_mailing' then 'bg-gray-100 border-gray-500'
    when 'rejected' then 'bg-red-100 border-red-500'
    else 'bg-gray-100 border-gray-500'
    end
  end
end
