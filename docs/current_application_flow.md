Perfect! Let's document the complete flow and verify everything is in place. I'll also identify what needs to be set up for Gmail integration.

## Current Application Flow

### 1. Campaign Creation & Contact Generation
**Location:** Campaign Planner UI (`/outreach_planner`)

```
User clicks "Campaign Planner" in nav
         ↓
Selects profile (e.g., "White Woman / 26")
Names campaign (e.g., "Winter 2024 Outreach")
         ↓
Reviews summary showing total eligible orgs
Clicks "START Outreach & AI Drafting Program"
         ↓
OutreachCampaignJob runs in background
         ↓
Creates OutreachContact records:
  - status: 'ready_for_email_outreach' (if email found)
  - status: 'needs_mailing' (if no email found)
  - contact_email: populated from org data
  - campaign_name: stored for tracking
         ↓
Job processes one org every 5 seconds
Creates OutreachLog entries for each
```

### 2. Email Sending (Daily Batch)
**Location:** Rake task (`bundle exec rake email_outreach:send_emails[50]`)

```
Run daily rake task with batch size (e.g., 50)
         ↓
Queries OutreachContact.where(status: 'ready_for_email_outreach')
         ↓
For each contact (up to batch limit):
  1. Load organization data
  2. Generate email using OutreachMailer
  3. Send via Gmail (johanna@johannalucilleroberts.com)
  4. Update status: 'ready_for_email_outreach' → 'pending'
  5. Set last_contact_at: Time.current
  6. Create OutreachLog with type: 'email_sent'
  7. Sleep 5 seconds between emails
         ↓
Shows stats: sent, failed, skipped
Shows remaining count
```

### 3. Response Tracking
**Location:** Outreach Tracker UI (`/outreach_contacts`)

```
Manual updates as responses come in:
  - 'pending' → 'accepted' (positive response)
  - 'pending' → 'rejected' (negative response)
  - 'pending' → 'needs_response' (needs clarification)

Each status change creates an OutreachLog entry
```

## What's Missing: Gmail Integration

You need to set up Gmail API access. Here's what needs to be done:

### New file: `config/initializers/gmail.rb`

```ruby
# Configure Gmail API settings
GMAIL_CONFIG = {
  from_email: "johanna@johannalucilleroberts.com",
  daily_limit: 50, # Adjust based on your Gmail sending limits
  rate_limit_seconds: 5 # Time between emails
}.freeze
```

### Updated file: `app/mailers/application_mailer.rb`

```ruby
class ApplicationMailer < ActionMailer::Base
  default from: GMAIL_CONFIG[:from_email]
  layout "mailer"
end
```

### Updated file: `config/environments/development.rb`

Add this configuration block for Gmail (you'll need to add similar to `production.rb`):

```ruby
# Around line 70, add:
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address: 'smtp.gmail.com',
  port: 587,
  domain: 'johannalucilleroberts.com',
  user_name: Rails.application.credentials.dig(:gmail, :username),
  password: Rails.application.credentials.dig(:gmail, :app_password),
  authentication: 'plain',
  enable_starttls_auto: true
}
config.action_mailer.perform_deliveries = true
config.action_mailer.raise_delivery_errors = true
```

### Gmail Setup Steps (Action Required)

You need to:

1. **Enable 2-Factor Authentication** on your Google Workspace account (if not already enabled)

2. **Generate an App Password:**
   - Go to: https://myaccount.google.com/apppasswords
   - Create a new app password for "Rails App"
   - Copy the 16-character password

3. **Store Credentials Securely:**
   ```bash
   EDITOR="code --wait" rails credentials:edit
   ```
   
   Add to the credentials file:
   ```yaml
   gmail:
     username: johanna@johannalucilleroberts.com
     app_password: YOUR_16_CHAR_APP_PASSWORD_HERE
   ```

4. **Test the Setup:**
   ```ruby
   # In rails console
   contact = OutreachContact.where(status: 'ready_for_email_outreach').first
   OutreachMailer.scholarship_inquiry(contact).deliver_now
   # Check if email arrives at the recipient
   ```

## Status Tracking Table

Here's how the `outreach_contacts` table rows update:

| Status | When It's Set | What It Means | Next Action |
|--------|---------------|---------------|-------------|
| `ready_for_email_outreach` | Campaign job creates contact | Email found, ready to send | Rake task will send |
| `needs_mailing` | Campaign job (no email) OR rake task (send failed) | Must use physical mail | Manual outreach |
| `pending` | After email sent successfully | Waiting for their response | Monitor inbox |
| `needs_response` | Manual update | They replied, need to respond | User action required |
| `accepted` | Manual update | They agreed to consider/help | Success! |
| `rejected` | Manual update | They declined | Archive |

## Daily Workflow

### Morning Routine:
```bash
# Send today's batch of 50 emails
bundle exec rake email_outreach:send_emails[50]

# Check the output for any failures
# Review the Outreach Tracker UI for status updates
```

### As Responses Come In:
1. Check your Gmail inbox (johanna@johannalucilleroberts.com)
2. Go to Outreach Tracker UI (`/outreach_contacts`)
3. Click "History" on the organization
4. Update status based on their response
5. Add notes in the log if needed

## Testing Before Going Live

### New file: `lib/tasks/email_outreach/test.rake`

```ruby
namespace :email_outreach do
  desc "Send a test email to yourself"
  task test: :environment do
    puts "Creating test outreach contact..."
    
    # Create a test organization if needed
    test_org = Organization.first
    
    test_contact = OutreachContact.create!(
      organization: test_org,
      status: :ready_for_email_outreach,
      contact_email: "johanna@johannalucilleroberts.com", # Send to yourself
      campaign_name: "Test Campaign"
    )
    
    puts "Sending test email to #{test_contact.contact_email}..."
    mail = OutreachMailer.scholarship_inquiry(test_contact)
    mail.deliver_now
    
    puts "✓ Test email sent! Check your inbox."
    puts "Subject: #{mail.subject}"
    
    # Clean up
    test_contact.destroy
  end
end
```

Run with:
```bash
bundle exec rake email_outreach:test
```

## Questions to Confirm:

1. **Do you have Google Workspace admin access** to generate app passwords?
2. **What daily sending limit** do you want? (Gmail allows ~500/day for Workspace, but 20-50 is safer)
3. **Do you want a test mode** that sends all emails to yourself first before going live?

Once you complete the Gmail setup steps, the entire flow will be operational!