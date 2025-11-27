# Architecture and Sequence Diagram: Grounding with Search

This document outlines the architecture and process flow of the web grounding system, as implemented in the `grounding:answer_question` Rake task.

## 1. System Architecture

The system is designed to answer a user's question by grounding it with information retrieved from a real-time web search. This ensures that the answers are up-to-date and based on publicly available information. The architecture consists of several key components working in concert.

### Core Components

*   **Rake Task (`grounding:answer_question`)**: The orchestrator of the entire process. It takes the user's question as input, calls the necessary services, manages the data flow between them, and presents the final result.

*   **GroundingService**: A dual-purpose service that interacts with the Large Language Model (LLM).
    1.  **Query Transformation**: Its `transform_query` method takes the user's raw question and uses an LLM to refine it into an optimal search engine query.
    2.  **Grounded Answering**: Its `answer_from_context` method takes the original question and the context fetched from the web, then uses the LLM to generate a final answer with citations based *only* on that context.

*   **WebSearchService**: This service is responsible for all interactions with the web.
    1.  **Search**: It takes a search query and uses an external web search engine to get a list of relevant URLs.
    2.  **Content Fetching**: It takes a URL and retrieves the raw content of the webpage.

*   **Large Language Model (LLM)**: An external AI service that performs two distinct tasks: refining the search query and generating the final answer from the provided context.

*   **Web Search Engine**: An external service (e.g., Google, SearXNG) that returns search results for a given query.

## 2. Sequence of Operations

The process follows a clear, multi-step sequence to ensure a high-quality, grounded answer.

1.  **Query Transformation**: The initial question is sent to the `GroundingService`, which uses the LLM to transform it into a more effective set of search terms.
2.  **Web Search**: The transformed query is passed to the `WebSearchService`, which executes the search and returns a list of the top URLs.
3.  **Content Fetching**: The Rake task iterates through the top URLs, instructing the `WebSearchService` to fetch the content from each page.
4.  **Context Assembly**: The Rake task concatenates the content from all fetched pages into a single `context` string.
5.  **Grounded Answer Generation**: The original question and the assembled `context` are sent to the `GroundingService`. It prompts the LLM to generate a JSON object containing the final answer and a list of citations (quotes and source URLs) that support the answer.
6.  **Display**: The Rake task parses the JSON and displays the final answer and its sources to the user.

## 3. Sequence Diagram

The following Python code, using the `diagrams` library, generates a sequence diagram that visualizes the entire process flow.

```python
from diagrams import Diagram, Cluster
from diagrams.onprem.client import User
from diagrams.generic.compute import Rack
from diagrams.generic.database import SQL
from diagrams.generic.network import Subnet
from diagrams.programming.framework import Rails
from diagrams.programming.flowchart import Document

with Diagram("Sequence Diagram: Grounding with Search", show=False, direction="TB"):
    
    user = User("Developer/User")

    with Cluster("Ruby on Rails Application"):
        rake_task = Rails("grounding:answer_question")
        
        with Cluster("Services"):
            grounding_service = Rack("GroundingService")
            web_search_service = Rack("WebSearchService")

    with Cluster("External Services"):
        llm = SQL("Large Language Model")
        search_engine = Subnet("Web Search Engine")

    web_pages = Document("Web Pages")

    # Sequence of events
    user >> rake_task

    # 1. Query Transformation
    rake_task >> grounding_service: "1. transform_query(question)"
    grounding_service >> llm: "2. POST /chat (for query transformation)"
    llm >> grounding_service: '3. returns { "search_query": "..." }'
    grounding_service >> rake_task: "4. returns transformed_query"
    
    # 2. Web Search
    rake_task >> web_search_service: "5. search(transformed_query)"
    web_search_service >> search_engine: "6. GET /search?q=..."
    search_engine >> web_search_service: "7. returns search_results (URLs)"
    web_search_service >> rake_task: "8. returns top_urls"
    
    # 3. Content Fetching (loop)
    rake_task >> web_search_service: "9. fetch_page_content(url)"
    web_search_service >> web_pages: "10. GET /page/content"
    web_pages >> web_search_service: "11. returns HTML content"
    web_search_service >> rake_task: "12. returns page_content (Rake task assembles context)"

    # 4. Grounded Answer Generation
    rake_task >> grounding_service: "13. answer_from_context(question, context)"
    grounding_service >> llm: "14. POST /chat (for final answer)"
    llm >> grounding_service: '15. returns JSON { answer, citations }'
    grounding_service >> rake_task: "16. returns parsed JSON response"
    
    # 5. Display
    rake_task >> user: "17. prints final answer and citations"

```
