# Local LLM Integration for Web Search and Email Extraction

This document outlines the architecture for integrating local Large Language Models (LLMs) and local search infrastructure into the application, focusing on the RAG (Retrieval-Augmented Generation) pipeline used for tasks like email extraction. This replaces the previous reliance on external services like the Google Gemini API for web search and reasoning.

The implementation builds upon experimental scripts found in `local_llm_experiments/search_engine_tool`.

## Key Local Infrastructure

The system interacts with three primary local services:

1.  **Local LLM Server (Chat/Instruction Model):**
    *   **Endpoint:** `http://10.0.0.202:8080`
    *   **Model:** `Meta-Llama-3.1-8B-Instruct-Q8_0.guff` (a quantized Llama 3.1 model)
    *   **Purpose:** Handles natural language understanding, query transformation, and final response generation (e.g., email extraction, grounded answers).
    *   **Interface:** Interacted with via the `ruby-openai` gem, presenting an OpenAI-compatible API.

2.  **Local Embedding Server:**
    *   **Endpoint:** `http://10.0.0.202:8081`
    *   **Purpose:** Generates vector embeddings for text. Crucial for semantic search and finding relevant document chunks.
    *   **Interface:** Direct HTTP POST requests.
    *   **Note on Endpoints and Payloads:** There are two distinct usages of this server:
        *   **`EmbeddingService`** (used by `RagSearchService` for semantic search and chunk embeddings): Uses the `/embeddings` (plural) endpoint and expects a JSON payload `{"content": "..."}`.
        *   **`KnowledgeBaseService`** (for persistent document storage, *not* directly part of the email RAG flow): Uses the `/embedding` (singular) endpoint and expects a JSON payload `{"input": "..."}`.
        This difference in endpoints and payloads should be noted for consistency if both are intended to interact with the same underlying model server.

3.  **Local Web Search Aggregator (SearXNG):**
    *   **Endpoint:** `http://localhost:8888`
    *   **Purpose:** Provides a privacy-respecting and local alternative to commercial search engines.
    *   **Interface:** HTTP requests to its `/search` endpoint.

## Core RAG Pipeline for Email Extraction (and Grounding)

The primary workflow for tasks like email extraction now leverages a RAG pipeline, orchestrated by the `RagSearchService`.

### 1. `app/services/rag_search_service.rb` (New Component)

*   **Purpose:** This service is the central orchestrator of the RAG pipeline. It manages the entire process from initial query to synthesized context.
*   **Details:**
    *   Takes an initial query and a `search_provider_class` (either `WebSearchService` for SearXNG or `GoogleSearchService` for Google Custom Search).
    *   Calls `GroundingService#transform_query` to enhance the initial user query using the local LLM.
    *   Executes a web search using the specified `search_provider_class`.
    *   Fetches content from top search results using `WebSearchService#fetch_page_content` (which employs `ferrum`).
    *   Splits the fetched content into smaller, more manageable text chunks.
    *   Generates vector embeddings for the original query and all text chunks using `EmbeddingService`.
    *   Performs a vector similarity search (cosine similarity) to identify the most relevant chunks.
    *   Assembles these relevant chunks into a "dense context" string, which is then passed to a final LLM call for extraction or answering.

### 2. `app/services/email_search_service.rb` (Modified)

*   **Change:** Extensively refactored to delegate the RAG process to `RagSearchService`.
*   **Details:**
    *   No longer directly interacts with Google Gemini API's `google_search` tool.
    *   Initializes `RagSearchService` with the user's query and a configurable search provider (`:searxng` or `:google`).
    *   Receives the synthesized context from `RagSearchService`.
    *   Calls `GroundingService#extract_email_with_llm` (which uses the local LLM via `ruby-openai`) to analyze the dense context and extract the final email address.
    *   Manages rate limiting for calls to the local LLM.

### 3. `app/services/grounding_service.rb` (Modified/New)

*   **Purpose:** Dedicated to LLM interactions, used for specific RAG steps.
*   **Details:**
    *   Uses the local LLM (via `ruby-openai`) for:
        *   `transform_query`: To refine user questions into effective search queries.
        *   `answer_from_context`: To generate grounded answers or extract specific information (like emails) from provided context, enforcing a structured JSON output with citations.

### 4. `app/services/web_search_service.rb` (New Component)

*   **Purpose:** Encapsulates web search and content fetching.
*   **Details:**
    *   `search` method: Queries a local SearXNG instance to get relevant URLs.
    *   `fetch_page_content` method: Uses the `ferrum` gem (a headless browser) to navigate to URLs, render JavaScript, and extract clean text content from web pages.

### 5. `app/services/embedding_service.rb` (Modified/New)

*   **Purpose:** Provides a unified interface for generating embeddings for both semantic search on `Organizations` and for text chunks within the RAG pipeline.
*   **Details:**
    *   Sends text to the local embedding server (port 8081, `/embeddings` endpoint) to obtain vector representations.
    *   The `to_embeddable_text` method on the `Organization` model defines the input for organization embeddings.

### 6. `app/models/web_document.rb` (New Component) & `db/migrate/20251123042339_create_web_documents.rb`

*   **Purpose:** `WebDocument` is an ActiveRecord model for storing web page content and its embedding persistently. The migration creates the `web_documents` table with `url`, `content`, `summary`, and a `vector` column for embeddings (dimension 768).
*   **Note:** While `KnowledgeBaseService` utilizes this model for persistent storage, `WebDocument` is *not* directly used by the `RagSearchService` in the on-the-fly email extraction RAG flow.

## Other Modified Components

*   **`Gemfile`:**
    *   Added `gem 'ferrum'`: For browser-based webpage fetching in `WebSearchService`.
    *   Added `gem 'ruby-openai'`: To communicate with the OpenAI-compatible local LLM endpoint.
*   **`lib/tasks/email_outreach.rake`:**
    *   Updated user-facing descriptions and error messages to reflect the local LLM setup.
    *   Removed references to "Gemini API", "daily quota", and "free tier".
    *   The `DailyLimitReached` error message now correctly indicates an issue with the local LLM server availability.
    *   Includes tasks for both `:searxng` and `:google` (Google Custom Search) as search providers for the email outreach.

## Configuration Notes

The current implementation hardcodes the URLs for the local LLM server, embedding server, and SearXNG instance within the service files (e.g., `EmailSearchService`, `EmbeddingService`, `WebSearchService`). For a production environment, these critical configurations should be externalized to a centralized Rails configuration, such as `config/credentials.yml.enc` or a custom initializer, to allow for easier management and environment-specific adjustments.
