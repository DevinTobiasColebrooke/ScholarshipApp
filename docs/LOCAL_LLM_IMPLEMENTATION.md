# Local LLM Email Search Implementation

This document outlines the changes made to replace the Google Gemini API-based email search with a self-hosted solution using a local SearXNG instance, a local LLM, and a local embedding server.

The new implementation is based on the scripts from the `local_llm_experiments/search_engine_tool` directory.

## New Components

The following files were added to the `ScholarshipApp` to support the new functionality:

### 1. `app/services/web_search_service.rb`

*   **Purpose:** This service encapsulates the functionality for performing web searches and fetching webpage content.
*   **Original File References:**
    *   The `search` method is a direct adaptation of the logic in `../../local_llm_experiments/search_engine_tool/search_tool.rb`, which uses a local SearXNG instance.
    *   The `fetch_page_content` method is an adaptation of the logic in `../../local_llm_experiments/search_engine_tool/fetch_webpage.rb`, which uses the `ferrum` gem to render pages and extract text content.

### 2. `app/models/web_document.rb`

*   **Purpose:** This is a new ActiveRecord model for interacting with the `web_documents` table. It includes the `has_vector` concern for `pgvector` support.

### 3. `db/migrate/20251123042339_create_web_documents.rb`

*   **Purpose:** This database migration creates the `web_documents` table.
*   **Schema:** The table includes columns for `url`, `content`, `summary`, and a `vector` column for `embedding` with a dimension of 768.

### 4. `app/services/knowledge_base_service.rb`

*   **Purpose:** This service is responsible for generating embeddings and storing document information in the new `web_documents` table.
*   **Original File References:**
    *   The logic is adapted from `../../local_llm_experiments/search_engine_tool/index_webpage.rb` and `../../local_llm_experiments/search_engine_tool/chat_with_search.rb`.
    *   The `get_embedding` method communicates with a local embedding server.
    *   The `store_document` method uses the `WebDocument` model to persist webpage data.

## Modified Components

The following existing files were modified:

### 1. `app/services/email_search_service.rb`

*   **Change:** This service was extensively refactored to orchestrate the new local services.
*   **Details:**
    *   It no longer uses the Google Gemini API's `google_search` tool.
    *   It now uses `WebSearchService` to perform a search and fetch content from the top results.
    *   It uses `KnowledgeBaseService` to store the fetched content and its embedding.
    *   It interacts with a local LLM via the `ruby-openai` gem to first summarize the content for storage and then to analyze the combined content to extract an email address.
    *   The core orchestration logic is adapted from `../../local_llm_experiments/search_engine_tool/chat_with_search.rb`.

### 2. `Gemfile`

*   **Change:** Added two new gems.
*   **Details:**
    *   `gem 'ferrum'`: For browser-based webpage fetching in `WebSearchService`.
    *   `gem 'ruby-openai'`: To communicate with the OpenAI-compatible local LLM endpoint.

### 3. `lib/tasks/email_outreach.rake`

*   **Change:** Updated user-facing descriptions and error messages.
*   **Details:**
    *   Removed references to "Gemini API", "daily quota", and "free tier".
    *   The `DailyLimitReached` error message was updated to reflect that the issue is now related to the availability of the local LLM server, not an external API limit.

## Configuration Notes

The new services (`WebSearchService`, `KnowledgeBaseService`, and `EmailSearchService`) currently have hardcoded URLs for the SearXNG instance, local LLM server, and embedding server. For a production environment, these should be moved to a centralized Rails configuration, such as `config/credentials.yml.enc` or a custom initializer.
