# Agent Flow for Email Discovery

This document traces the step-by-step process of how the system finds a contact email for a given organization. It clarifies the roles of the different services and explains how the LLM is used in the workflow.

## Overview

The primary goal is to find a contact email for an organization by searching the web, fetching relevant pages, and using a local LLM to analyze the content. The process is orchestrated by the `EmailSearchService`.

## Step-by-Step Flow

The process is initiated by running a Rake task, such as `rake email_outreach:find_emails`.

### Step 1: Initiation (Rake Task)

1.  The `email_outreach:find_emails` task selects an `Organization` from the database.
2.  It instantiates the main agentic service: `EmailSearchService.new(organization)`.
3.  It calls the `.find_email` method to begin the discovery process for that organization.

### Step 2: Web Search (Single Call)

1.  Inside `EmailSearchService`, the `search_and_extract_email` method begins.
2.  It first builds a targeted search query (e.g., "The Scholarship Foundation Inc. scholarship contact email").
3.  It makes a **single call** to `WebSearchService.search(query)`. This service sends a request to the local SearXNG instance and returns a list of relevant URLs.

### Step 3: Content Fetching Loop (The "Browsing" Phase)

This is the core of the "browsing" activity. The `EmailSearchService` does not ask the LLM to browse; instead, it executes a pre-defined loop to gather information.

1.  The service iterates through the top **3 URLs** returned from the web search.
2.  **For each URL in the loop**, the following actions occur:
    *   **Fetch Content:** `WebSearchService.fetch_page_content(url)` is called. This uses the `ferrum` gem to launch a headless browser, navigate to the URL, and extract the clean text content from the page.
    *   **Summarize Content (1st LLM Call per page):** The fetched text is passed to the `summarize_text_with_llm` method. This method calls the local LLM with a prompt asking it to create a concise summary of the text (max 150 words).
    *   **Store Knowledge:** The full page content, along with the LLM-generated summary, is passed to `KnowledgeBaseService.store_document`. This service generates a vector embedding of the content and saves the URL, content, summary, and embedding to the `web_documents` table in the database.
    *   **Collect Snippets:** A snippet of the fetched content (up to 2000 characters) is stored in a temporary array for the final extraction step.

### Step 4: Email Extraction (Final LLM Call)

1.  After the loop has completed, `EmailSearchService` has a collection of content snippets from the top 3 web pages.
2.  It combines these snippets into a single, large block of text.
3.  It makes a **final call** to the local LLM via the `extract_email_with_llm` method.
4.  The prompt for this call is highly specific: it instructs the LLM to act as an "expert email address extractor" and to find the most relevant email address within the provided text, returning **only** the email or the text "not_found".

### Step 5: Final Output

1.  The `EmailSearchService` receives the response from the LLM.
2.  It cleans and validates the response. If a valid email is found, it is returned. If the response is "not_found" or invalid, `nil` is returned.
3.  The Rake task receives this final result and updates the database accordingly.

## Clarification: How the LLM "Browses"

A key point of interest is when the LLM calls tools multiple times to browse the site.

In the current implementation, **the LLM does not decide to browse or call browsing tools.** The workflow follows a "Plan-and-Execute" model where the "plan" is simple and hardcoded into the `EmailSearchService`:

1.  **Plan:**
    *   Search the web once.
    *   Visit the top 3 URLs.
    *   Collect content from each.
    *   Analyze the collected content to find an email.

2.  **Execution:**
    *   The `EmailSearchService` executes this plan.
    *   The browsing (i.e., fetching page content) happens within a standard Ruby loop, not as a result of the LLM requesting it.
    *   The LLM is used as a powerful data processing tool at two key points: for **summarization** of each page and for the final **extraction** of the email from the combined text.

This approach is efficient and predictable. An alternative, more complex agentic workflow (like a ReAct agent) would involve the LLM in a loop of `Thought -> Action -> Observation`, where the LLM might decide to perform another search or visit another link based on what it finds. The current system is not designed this way; it uses the LLM for analysis, not for autonomous browsing decisions.
