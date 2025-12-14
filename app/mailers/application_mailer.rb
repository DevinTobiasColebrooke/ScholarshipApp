class ApplicationMailer < ActionMailer::Base
  default from: GMAIL_CONFIG[:from_email]
  layout "mailer"
end
