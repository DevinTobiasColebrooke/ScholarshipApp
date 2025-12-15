class OutreachMailer < ApplicationMailer
  def scholarship_inquiry(outreach_contact)
    @contact = outreach_contact
    @organization = outreach_contact.organization
    @recipient_email = outreach_contact.contact_email || outreach_contact.inferred_contact_email

    mail(
      to: @recipient_email,
      subject: "Inquiry: Disney Legacy Scholar Seeking Micro-Grant / Book Fund Support"
    )
  end
end
