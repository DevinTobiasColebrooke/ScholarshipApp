# Agent Flow for Email Discovery (RAG-based)

This document traces the step-by-step process of how the system finds a contact email for a given organization using a Retrieval-Augmented Generation (RAG) pipeline. It clarifies the roles of the different services and explains how the LLM is used in the workflow.

## Overview

The primary goal is to find a contact email by performing a web search, semantically ranking the retrieved content to find the most relevant information, and using a local LLM to extract the email address from that specific context. The process is initiated by `EmailSearchService` but the core RAG logic is orchestrated by `RagSearchService`.

## Step-by-Step Flow

The process is typically initiated by running a Rake task, such as `rake email_outreach:find_emails`.

### Step 1: Initiation (Rake Task)

1.  The Rake task selects an `Organization` from the database.
2.  It instantiates `EmailSearchService.new(organization, search_provider: :searxng)`.
3.  It calls the `.find_email` method, which in turn calls the internal `search_and_extract_email` method to begin the discovery process.

### Step 2: Delegation to RAG Service

1.  `EmailSearchService` does not perform the search and retrieval loop itself. Instead, it delegates the entire context-building process to the `RagSearchService`.
2.  It calls `RagSearchService.new(...).search_and_synthesize`, passing in the search query and the configured search provider class.

### Step 3: Retrieval-Augmented Generation (Orchestrated by `RagSearchService`)

This is the core of the agentic workflow, where the system retrieves and synthesizes information.

1.  **Query Transformation:** The `RagSearchService` first calls the local LLM (via `GroundingService`) to refine the initial search query (e.g., "contact for The Scholarship Foundation") into a more optimal one for a search engine.

2.  **Web Search:** The service executes the search using the specified provider (`WebSearchService` or `GoogleSearchService`) and gets back a list of top URLs.

3.  **Content Fetching & Chunking:** `RagSearchService` fetches the content from the top URLs using a headless browser (`ferrum`) and splits the text into smaller, manageable "chunks".

4.  **Embedding & Semantic Ranking:**
    *   The service generates a vector embedding for the **original query** using the `EmbeddingService`.
    *   It then generates vector embeddings for **every text chunk** in parallel.
    *   It calculates the cosine similarity between the query's embedding and each chunk's embedding. This allows it to find the chunks that are most semantically relevant to the user's goal, rather than just relying on keyword matches.

5.  **Dense Context Synthesis:** The text from only the highest-scoring, most relevant chunks is assembled into a single, dense `context` string. This highly relevant context is then returned to the `EmailSearchService`.

### Step 4: Email Extraction (Final LLM Call in `EmailSearchService`)

1.  `EmailSearchService` receives the dense `context` from `RagSearchService`.
2.  It makes a **final call** to the local LLM via the `extract_email_with_llm` method.
3.  The prompt for this call is highly specific: it instructs the LLM to act as an "expert email address extractor" and find the most relevant email address *only within the provided dense context*, returning just the email or "not_found".

### Step 5: Final Output

1.  `EmailSearchService` cleans and validates the LLM's response.
2.  The Rake task receives this final result (`email` or `nil`) and updates the database accordingly.

## Clarification: How the System "Browses" and Uses the LLM

In the current implementation, **the LLM does not decide when or what to browse.** The workflow follows a sophisticated "Plan-and-Execute" model.

1.  **Plan:** The "plan" is the RAG pipeline hardcoded into `RagSearchService`: transform query -> search -> fetch -> chunk -> embed -> rank -> synthesize context.

2.  **Execution:** The services execute this plan programmatically. The "browsing" (fetching page content) happens as a deterministic step in the plan.

3.  **LLM's Role:** The LLM is used as a powerful analysis tool at two distinct points, not as a decision-making agent in a loop.
    *   **At the beginning:** To refine the search query for better retrieval results.
    *   **At the end:** To perform a targeted extraction from the highly relevant, synthesized context.

This architecture is more advanced and effective than the previously documented simple loop. It uses semantic understanding to find the most relevant pieces of information across multiple web pages before presenting them to the LLM, leading to more accurate and efficient information extraction.

