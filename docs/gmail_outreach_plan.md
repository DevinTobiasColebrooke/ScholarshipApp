# Plan for Email Outreach via Google Workspace

This document outlines the proposed plan for sending personalized emails to the ~1560 organizations for which contact emails have been successfully identified. This process will leverage a Google Workspace account to send emails programmatically.

## 1. Objective

The primary goal is to send a high-quality, personalized email to each of the 1560 target organizations. The emails will be sent from a designated Google Workspace email account, using a standardized template.

## 2. Core Components & Implementation Plan

To achieve this, we will need to implement several key components.

### 2.1. Authentication with Google Workspace

To send emails through a Google account, the application must be authorized to use the Gmail API. This is the most critical and complex part of the setup.

**Proposed Implementation:**

1.  **Google Cloud Project Setup:**
    *   A new project will be created in the Google Cloud Console.
    *   The **Gmail API** will be enabled for this project.
2.  **OAuth 2.0 Consent Screen:**
    *   An OAuth consent screen will be configured. This is what the user will see when authorizing the application. It will need to be configured for an "Internal" or "External" app, depending on the Workspace setup.
3.  **OAuth 2.0 Credentials:**
    *   OAuth 2.0 client credentials (a `client_id` and `client_secret`) will be generated. These will be stored securely in Rails' encrypted credentials (`credentials.yml.enc`).
4.  **Authorization Flow:**
    *   A new Rake task or a secure web interface will be created to guide the user through a one-time authorization process. This process will grant the application a **refresh token**, which can be used to generate new access tokens without requiring user interaction every time.
    *   The refresh token will also be stored securely in Rails' credentials.

**Questions for Setup:**

*   **Which Google Workspace account should be used for sending the emails?** Please provide the email address that will be the sender.
*   **Will the person setting this up have the necessary permissions in Google Cloud and Google Workspace to create projects and grant API access?**

### 2.2. Email Template

A dynamic email template is required. The template will be personalized for each organization.

**Proposed Implementation:**

*   The template will be stored either as a view in `app/views/` (if using Action Mailer) or as a string in a configuration file.
*   It will use placeholders that will be replaced with data from the `Organization` record.

**Action Item: Define the Email Template**

Please provide the content for the email template. What should be the **subject** and **body** of the email? Please indicate where the following placeholders should be inserted:

*   `[Organization Name]`
*   `[Your Name/Project Name]`
*   Any other dynamic information from the `Organization` or `Grant` models.

**Example Template Structure:**

*   **Subject:** Inquiry Regarding Scholarship Opportunities from [Organization Name]
*   **Body:**
    > Dear [Organization Name] Team,
    >
    > I am writing to you today on behalf of [Your Name/Project Name]. We are researching scholarship-granting organizations, and your foundation, [Organization Name], was identified as a potential supporter of students.
    >
    > ... (further details about the inquiry) ...
    >
    > Thank you for your time.
    >
    > Sincerely,
    > [Your Name]

### 2.3. Email Sending Mechanism

A new mechanism will be created to handle the sending of emails in bulk, leveraging existing data structures.

**Proposed Implementation:**

1.  **New Rake Task:** A new Rake task, `outreach:send_emails`, will be created in `lib/tasks/outreach.rake`.
2.  **Logic:**
    *   The task will fetch all `Organization` records that have a `org_contact_email` and are associated with an `OutreachContact` record whose `status` is `'needs_outreach'`.
    *   It will initialize a service that can interact with the Gmail API using the stored OAuth 2.0 credentials.
    *   For each such organization and its `OutreachContact`, it will:
        *   Retrieve the `contact_email` from the `OutreachContact` record (which should ideally be the same as `org_contact_email` or a specific email for the campaign).
        *   Personalize the email template using information from the `Organization` and potentially `OutreachContact`.
        *   Use the Gmail API to send the email to the `contact_email`.
        *   Update the `OutreachContact` status to `contacted`.
        *   Create a new `OutreachLog` entry, associated with the `OutreachContact`, to record the sending event, including the recipient, subject, and body of the sent email.

### 2.4. Tracking and Logging

It's important to track the outreach process using the existing database models.

**Proposed Implementation:**

*   **`OutreachContact` Status:** The `status` attribute of the `OutreachContact` model will be the primary way to track the state of each organization's outreach journey.
    *   `needs_outreach`: Initial state for organizations identified for email sending.
    *   `contacted`: Set after an email has been successfully sent.
    *   (Future states could include `responded`, `bounced`, etc.)
*   **`OutreachLog` Entries:** The `OutreachLog` model will be used to record each significant event in the outreach process.
    *   Each email sending attempt will result in a new `OutreachLog` entry, associated with the respective `OutreachContact`.
    *   The `log_type` attribute will describe the event (e.g., 'email_sent').
    *   The `details` attribute will contain relevant information such as the subject, body of the sent email, and any API responses.

### 2.5. Safety and Rate Limiting

To avoid being flagged as a spammer by Google or recipient servers, we must adhere to best practices.

**Proposed Implementation:**

*   **Sending Rate:** The sending Rake task will include a delay (e.g., 5-10 seconds) between each email to avoid sending too rapidly.
*   **Google's Limits:** The Gmail API has its own usage limits. We will need to be mindful of these, although they are generally generous for this scale.
*   **Unsubscribe/Opt-Out:** For long-term outreach, we would need to consider adding an unsubscribe link, but for this initial, targeted outreach, it may not be necessary.

**Question:**

*   **Are there any specific "from" names or reply-to addresses that should be used?**

This plan provides a roadmap for the implementation. The next step is to get answers to the questions above to fill in the missing details.