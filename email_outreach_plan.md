# Plan to Find and Store Organization Emails

This document outlines the plan to find and store email addresses for the 3,858 organizations that match the "white woman /26" profile.

### 1. Identify Target Organizations

*   **Create a Rake Task:** A new Rake task will be created to encapsulate the entire process. This will make it easy to run and re-run the process as needed.
*   **Use Existing Scope:** The `Organization.profile_white_woman_26` scope will be used to fetch the list of 3,858 target organizations.

### 2. Process Each Organization

*   **Iterate and Validate:** The Rake task will iterate through each organization. For each organization, it will first check for the presence of a `website_address_txt`.

### 3. Find Email Address

*   **Primary Method: AI-Powered Search:**
    *   Utilize the Gemini API to analyze the organization's website and find the most relevant contact email.
    *   The AI will act as a researcher, attempting to locate the best email for scholarship inquiries.
    *   This approach is expected to be more effective than simple scraping, as it can understand context and navigate complex site structures.
    *   To stay within the free tier, API usage will be monitored and potentially rate-limited.
*   **Outcome:**
    *   If an email is found, it will be stored.
    *   If no email can be found, the organization will be marked for manual mail outreach (`status`: 'needs_mailing').
*   **Respectful Interaction:**
    *   All web requests will include a user-agent.
    *   Requests will be spaced out to avoid overwhelming servers.

### 4. Update Organization and Outreach Status

*   **Email Found:**
    *   The `recipient_email_address_txt` field on the `Organization` record will be updated with the found email address.
    *   An `OutreachContact` record will be created or updated with:
        *   `status`: 'needs_outreach'
        *   `contact_email`: The found email address.
        *   `campaign_name`: "White Woman/26 Profile"
*   **Email Not Found:**
    *   An `OutreachContact` record will be created or updated with:
        *   `status`: 'needs_mailing'
        *   `campaign_name`: "White Woman/26 Profile"

### 5. Logging and Error Handling

*   **Progress Logging:** The Rake task will log its progress, including the number of organizations processed, emails found, and errors encountered.
*   **Error Handling:** The scraper will be built to handle common errors like network issues, timeouts, and invalid URLs.

### Caveats and Blockers

*   **Website Complexity:** Modern websites can be complex, and a simple scraper may not be able to handle all cases (e.g., JavaScript-rendered content).
*   **Anti-Scraping Measures:** Some websites may have measures in place to block scrapers.
*   **Email Obfuscation:** Websites may obfuscate email addresses to prevent scraping.
*   **Rate Limiting:** Making too many requests too quickly can result in being blocked.*
