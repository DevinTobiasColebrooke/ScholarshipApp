# Recommendations for Improving the Grounding Search Tool

## 1. Executive Summary

The current grounding search tool uses a live web search for every query. Given that each lookup is for new, unique information (a "one-time lookup") and there's no benefit to caching past results, the focus shifts from building a persistent knowledge base to **maximizing the quality and relevance of each real-time search**.

This document outlines strategies to significantly improve the accuracy, efficiency, and context quality of the search-to-LLM pipeline for one-time lookups.

---

## 2. Recommendation: Optimize Real-Time Context Processing

For one-time lookups, the goal is to extract the most relevant information from a live web search as effectively as possible. This requires a more sophisticated, in-memory retrieval process.

### Proposed Workflow:

1.  **LLM-Powered Query Transformation (Implemented):**
    *   **Status:** This feature has been implemented and is live in the `grounding:answer_question` Rake task.
    *   Before executing any search, a preliminary LLM call refines the user's raw question into an optimal, specific search engine query. This ensures SearXNG receives the best possible input for retrieving relevant documents.
    *   **Example:** A user asks, "What about scholarships for white women?" An LLM could transform this into multiple effective queries like "scholarships for caucasian women", "grants for female students eligibility", or "merit-based scholarships not restricted by ethnicity".

2.  **Widen the Initial Web Search:**
    *   Instead of fetching just the top 3 URLs, instruct `WebSearchService` to retrieve a larger initial set of URLs from SearXNG (e.g., the top 10-15 results). This increases the pool of potential relevant documents.

3.  **Implement a Request-Scoped RAG Process (In-Memory Retrieval):**
    *   **Content Fetching & Advanced Extraction:** For each of the top N URLs from the widened search, fetch its full content. Crucially, use an advanced HTML content extractor (like a `readability` library) to remove boilerplate (navbars, footers, ads), ensuring you get only the main article text.
    *   **Intelligent Chunking:** Break the extracted main article text from each fetched document into smaller, semantically meaningful chunks (e.g., paragraphs or sections, ideally 200-300 words).
    *   **In-Memory Embedding:** For the current request, generate vector embeddings for *all* these chunks in memory.
    *   **Second-Pass Retrieval:** Compare the embedding of the user's transformed query against the embeddings of all generated chunks. Select the top 5-7 most relevant chunks (regardless of their original document source).
    *   **Context Assembly:** Concatenate these highly relevant chunks to form a dense, focused context. This context is then passed to the main `GroundingService` LLM.

### Benefits:

*   **Maximized Relevance:** By processing more initial results and using embeddings to pick the most relevant *chunks*, the LLM receives a far more precise and useful context.
*   **Efficiency:** Focuses content extraction and LLM processing only on the most promising snippets of text.
*   **Accuracy:** Reduces the likelihood of the LLM hallucinating or being confused by irrelevant information within a broad context window.

---

## 3. Recommendation: Enhance Context Quality Through Advanced Extraction

This recommendation is central to a one-time lookup, as the quality of immediately-fetched content directly impacts the answer.

*   **Improve HTML Content Extraction:** The current `WebSearchService` using `Nokogiri` to just remove `<script>` and `<style>` tags is a good start, but it often leaves non-essential "chrome" text like navigation bars, footers, and sidebars.
    *   **Recommendation:** Integrate a library designed for extracting only the main article content (e.g., a `readability` library for Ruby, such as [`readability-parser`](https://github.com/sreeix/readability-parser)). This will provide much cleaner text for both generating embeddings and for the final LLM context.

---

## 4. Recommendation: Advanced Prompting & Re-ranking

### 4.1. Few-Shot Prompting for JSON Formatting

The `GroundingService` prompt asks the LLM to return a JSON object. To ensure reliability for a one-time lookup (where no prior learning occurs), including a high-quality example of the desired output directly in the system prompt can be highly effective.

*   **Recommendation:** Add a static, well-formed example to the `GroundingService` system prompt, demonstrating exactly what JSON structure and content is expected. This reinforces the instructions and significantly reduces formatting errors.

### 4.2. Implement an Initial Re-ranking Step (Optional, for Speed vs. Quality Trade-off)

If fetching and processing 10-15 URLs is too slow, a faster re-ranking step can be inserted.

*   **Workflow:** After getting the initial 10-15 URLs from SearXNG, use a lightweight analysis (e.g., keyword density, title/description relevance to the query) or a very fast, small re-ranker model.
*   **Purpose:** This step quickly filters down the list to the top 3-5 *most promising* URLs *before* fetching their full content. This can significantly reduce the latency and resource usage associated with `Ferrum` and content parsing.