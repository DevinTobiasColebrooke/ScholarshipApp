class AiEmailDraftingJob < ApplicationJob
  queue_as :default

  def perform(outreach_contact_id, profile_name)
    contact = OutreachContact.find_by(id: outreach_contact_id)
    return unless contact

    Rails.logger.info "Starting AI email draft for #{contact.organization.name} (Profile: #{profile_name})"

    # --- AI/Local Model Integration Logic Goes Here ---
    # 1. Text Embedding: (nomic-embed-text)
    #    # ExternalAiService.get_embedding(...)

    # 2. Local AI Model: (llama.cpp/Ollama)
    #    # ExternalAiService.draft_email(...)

    # For now, simulate the result:
    officer = contact.organization.principal_officer_nm.presence || 'Director'
    drafted_email_body = "Dear #{officer},\n\nI am writing on behalf of a white woman, 26, matching the criteria of your foundation, which we identified through our tailored search process. We believe our applicant aligns perfectly with your mission focused on [MENTION MISSION HERE]...\n\nSincerely,\nApplicant Support."

    # 3. Log the successful draft
    contact.outreach_logs.create(
      log_type: 'ai_draft_complete',
      details: "AI Draft Ready for review.\n\n--- Draft ---\n#{drafted_email_body.truncate(500)}"
    )

    Rails.logger.info "AI email draft complete for #{contact.organization.name}"
  rescue StandardError => e
    Rails.logger.error "AI Email Drafting failed for contact #{outreach_contact_id}: #{e.message}"
    contact.outreach_logs.create(log_type: 'status_update', details: "AI Draft Failed: #{e.message.truncate(200)}") if contact
  end
end
