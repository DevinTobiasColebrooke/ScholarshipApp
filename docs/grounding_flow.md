# Replicating Google Search Grounding with Local LLM and SearxNG

This document outlines the flow of the Google Search Grounding tool as described in the ADK documentation and a plan to replicate this functionality using our existing local LLM and SearxNG infrastructure.

## Google Search Grounding Flow (from ADK Docs)

The Google Search Grounding tool enables an AI agent to access and use real-time information from the web to answer queries. The flow is as follows:

1.  **LLM Invocation**: The agent's Large Language Model (LLM) first determines if a query requires up-to-date, external information. If so, it decides to invoke the `google_search` tool.
2.  **Tool Call**: The `google_search` tool is called with the user's query.
3.  **Grounding Service**: The tool communicates with a grounding service, which queries the Google Search Index and retrieves relevant web pages and snippets.
4.  **Context Integration**: The fetched content is integrated into the LLM's context.
5.  **Response Generation**: The LLM generates a final response based on the original query and the newly added context from the web search.
6.  **Attribution**: The response includes `groundingMetadata`, which contains source URLs and links specific sentences in the answer back to the web pages they came from, ensuring verifiability.

## Replication Plan for Our Project

We can replicate this grounding flow by orchestrating our existing services (`WebSearchService`, `EmbeddingService`, and the local LLM). The goal is to create a Rake task or a service that takes a question, searches the web, and generates an answer grounded in the search results, complete with citations.

### Step-by-Step Replication Flow

1.  **Initiation (Rake Task or Service)**:
    *   A new Rake task, e.g., `rake answer_question[question]`, will be created to initiate the process.
    *   This task will take a question as an argument.

2.  **Web Search (Tool Call)**:
    *   The task will call `WebSearchService.search(question)` to query SearxNG. This is the equivalent of the `google_search` tool call.

3.  **Content Retrieval and Context Building**:
    *   The service will loop through the top 3 search results returned by SearxNG.
    *   For each URL, it will call `WebSearchService.fetch_page_content(url)` to get the text content of the page.
    *   The content from all fetched pages will be compiled into a single context string, with each source clearly delineated (e.g., by including the URL before the content of each page).

4.  **Grounded Response Generation (LLM Call)**:
    *   A new method will be created to send the combined context and the original question to the local LLM.
    *   The prompt will be carefully engineered to instruct the LLM to:
        *   Answer the question based *only* on the provided text context.
        *   Cite the sources for its answer by referencing the URLs provided in the context.
        *   Produce a structured output, such as a JSON object, that includes the answer and a list of citations. For example:
            ```json
            {
              "answer": "The capital of France is Paris, which is also its most populous city.",
              "citations": [ { "source_url": "https://en.wikipedia.org/wiki/Paris", "text": "Paris is the capital and most populous city of France." } ]
            }
            ```

5.  **Displaying the Result**:
    *   The Rake task will parse the JSON response from the LLM and display the answer along with its citations in a user-friendly format.

### Example Implementation in a Rake Task

```ruby
# lib/tasks/grounding_test.rake
namespace :grounding do
  desc "Answer a question using web search grounding"
  task :answer, [:question] => :environment do |_, args|
    question = args[:question]
    puts "Answering question: '#{question}'"

    # 1. Search
    search_results = WebSearchService.search(question)
    top_urls = search_results['results'].first(3).map { |r| r['url'] }

    # 2. Fetch and build context
    context = ""
    top_urls.each do |url|
      content = WebSearchService.fetch_page_content(url)
      context += "Source URL: #{url}\nContent:\n#{content}\n\n---\n\n" if content
    end

    # 3. Generate grounded response from LLM
    # (This would call a new method in a service that constructs the prompt
    # and sends it to the LLM)
    # grounded_response = GroundingService.new.answer_from_context(question, context)

    # 4. Display result
    # puts "Answer: #{grounded_response['answer']}"
    # puts "Sources:"
    # grounded_response['citations'].each do |citation|
    #   puts "- #{citation['source_url']}"
    # end
  end
end
```

This plan provides a clear path to replicating the Google Search Grounding flow using our existing local LLM and SearxNG setup.
