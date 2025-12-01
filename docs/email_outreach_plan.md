# Plan to Find and Store Organization Emails

This document outlines the plan to find and store email addresses for the 3,858 organizations that match the "white woman /26" profile.

### Components

#### `app/services/email_search_service.rb`

This service is responsible for using the Gemini API to find contact email addresses for a given organization. It is designed to be resilient to API rate limits by automatically cycling through a list of available Gemini models.

*   **Purpose:** To find email addresses for a given organization by name, using the Gemini API's Google Search capabilities, with built-in rate limiting and model switching.
*   **Initialization:** Takes an `organization` object as an argument. Requires the `GEMINI_API_KEY` environment variable to be set.
*   **Model Switching:**
    *   Maintains a list of Gemini models (e.g., `gemini-pro`, `gemini-1.5-flash`).
    *   If a request fails with a rate limit error (HTTP 429), the service automatically switches to the next model in the list and retries the request.
    *   This allows the process to continue even if a daily limit for a specific model is reached.
*   **Rate Limiting:**
    *   Includes a per-minute rate limiter to stay within the 60 queries per minute (QPM) limit of the free tier.
*   **`find_email` method:**
    *   Orchestrates the process of performing an AI-powered email search.
    *   Handles `AiSearchError`, including retrying with a different model on rate limit errors.
    *   Returns the found email address or `nil` if not found or an error occurs after all retries.
*   **`search_with_ai` (private):**
    *   Constructs a prompt for the current Gemini model, using the organization's name and asking for the email of the 'contributing manager' or a general contact.
    *   Uses the appropriate search tool (`google_search_retrieval` or `google_search`) based on the model.
    *   Sends a POST request to the Gemini API.
    *   Parses the AI's response to extract the email address.

#### `lib/tasks/email_outreach.rake`

This Rake task automates the process of finding and storing email addresses for a specific campaign.

*   **Task Name:** `email_outreach:find_emails`
*   **Purpose:** To iterate through a predefined set of organizations, use the `EmailSearchService` to find their contact emails, and update their `OutreachContact` status accordingly.
*   **Process:**
    1.  **Identify Target Organizations:** Fetches organizations matching the `Organization.profile_white_woman_26` scope that have a `website_address_txt` and have not been processed yet for this campaign.
    2.  **Iterate and Search:** Loops through each identified organization.
    3.  **Find Email:** Instantiates `EmailSearchService` with the organization's `website_address_txt` and calls `find_email`.
    4.  **Update Records:**
        *   If an email is found, updates the `organization.org_contact_email` and creates/updates an `OutreachContact` record with `status: 'needs_outreach'` and the found email.
        *   If no email is found, creates/updates an `OutreachContact` record with `status: 'needs_mailing'`.
    5.  **Logging:** Provides console output on the progress, including the number of organizations processed, emails found, and emails not found.

### 1. Identify Target Organizations

*   **Create a Rake Task:** A new Rake task will be created to encapsulate the entire process. This will make it easy to run and re-run the process as needed.
*   **Use Existing Scope:** The `Organization.profile_white_woman_26` scope will be used to fetch the list of 3,858 target organizations.

### 2. Process Each Organization

*   **Iterate and Validate:** The Rake task will iterate through each organization. For each organization, it will first check for the presence of a `website_address_txt`.

### 3. Find Email Address

*   **Primary Method: AI-Powered Search:**
    *   Utilize the Gemini API's built-in Google Search tool to find the most relevant contact email for the organization's website.
    *   The AI will act as a researcher, leveraging its search capabilities to locate the best email for scholarship inquiries.
    *   This approach is expected to be more effective than traditional scraping, as it can understand context and navigate complex site structures through its integrated search.
    *   To stay within the free tier, API usage will be monitored and potentially rate-limited.
*   **Outcome:**
    *   If an email is found, it will be stored.
    *   If no email can be found, the organization will be marked for manual mail outreach (`status`: 'needs_mailing').
*   **Respectful Interaction:**
    *   All web requests will include a user-agent.
    *   Requests will be spaced out to avoid overwhelming servers.

### 4. Update Organization and Outreach Status

*   **Email Found:**
        The `org_contact_email` field on the `Organization` record will be updated with the found email address.
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

### Gemini API Usage and Rate Limiting

The process relies on the Google Gemini API's free tier, which has certain limitations:

*   **Queries Per Minute (QPM):** The free tier for models like `gemini-pro` is limited to 60 queries per minute. The `EmailSearchService` has a built-in rate limiter to stay within this limit.
*   **Daily Limits:** While not always explicitly documented, free tiers often have daily usage limits. If a daily limit is hit for one model, the process may fail for the rest of the day for that model.
*   **Model Availability:** The availability of free-tier models can change.

To mitigate these issues, the `EmailSearchService` has been designed with the following features:
*   **Automatic Model Switching:** The service maintains a list of compatible Gemini models. If one model fails due to rate limiting, it automatically switches to the next available model and retries the request. This provides resilience against hitting daily limits for a single model.
*   **Graceful Failure:** If all available models are rate-limited or an unrecoverable error occurs, the process for that organization will fail gracefully, and the Rake task will move on to the next one. The organization will be marked as 'needs_mailing'.

### Caveats and Blockers

*   **Website Complexity:** Modern websites can be complex, and a simple scraper may not be able to handle all cases (e.g., JavaScript-rendered content).
*   **Anti-Scraping Measures:** Some websites may have measures in place to block scrapers.
*   **Email Obfuscation:** Websites may obfuscate email addresses to prevent scraping.
*   **Rate Limiting:** Making too many requests too quickly can result in being blocked.*
