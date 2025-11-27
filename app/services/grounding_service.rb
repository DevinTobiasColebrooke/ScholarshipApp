require 'openai'
require 'json'

class GroundingService
  # Using the same LLM configuration as the EmailSearchService
  LLM_BASE_URL = "http://10.0.0.202:8080".freeze
  LLM_MODEL_NAME = "Meta-Llama-3.1-8B-Instruct-Q8_0.guff".freeze
  LLM_API_KEY = "dummy".freeze

  def initialize
    @llm_client = OpenAI::Client.new(access_token: LLM_API_KEY, uri_base: LLM_BASE_URL, request_timeout: 120)
  end

  def answer_from_context(question, context)
    system_prompt = <<~PROMPT
You are an expert question-answering agent. Your task is to answer the user's question based *only* on the provided text context.
The context consists of content fetched from different web pages, each prefixed with its source URL.

When you answer, you must follow these rules:
1.  Base your answer entirely on the information given in the context. Do not use any outside knowledge.
2.  Your response must be a single JSON object with two keys: "answer" and "citations".
3.  The "answer" key should contain the plain text answer to the question.
4.  The "citations" key should be an array of objects, where each object has two keys: "source_url" and "text". The "text" should be the exact sentence or phrase from the context that supports your answer.

SPECIAL INSTRUCTIONS:
- If the question is a request to find a specific piece of information (like an email address), the "answer" should be ONLY that piece of information.
- If the context does not contain the answer to the question, the "answer" should be 'not_found'. In this case, the "citations" array should be empty.

Example for a general question:
{
  "answer": "The capital of France is Paris, which is also its most populous city.",
  "citations": [
    { "source_url": "https://en.wikipedia.org/wiki/Paris", "text": "Paris is the capital and most populous city of France." }
  ]
}

Example for information extraction (email found):
{
  "answer": "contact@example.com",
  "citations": [
    { "source_url": "https://example.com/contact", "text": "You can reach us at contact@example.com." }
  ]
}

Example when information is not found:
{
  "answer": "not_found",
  "citations": []
}
PROMPT

    user_prompt = "Context:\n#{context}\n\nQuestion: #{question}"

    messages = [
      { role: "system", content: system_prompt.strip },
      { role: "user", content: user_prompt }
    ]

    begin
      response = @llm_client.chat(
        parameters: {
          model: LLM_MODEL_NAME,
          messages: messages,
          temperature: 0.0, # Low temperature for factual, grounded answers
          response_format: { type: "json_object" } # Instruct the model to return JSON
        }
      )
      
      json_response_text = response.dig("choices", 0, "message", "content")&.strip
      
      if json_response_text
        JSON.parse(json_response_text)
      else
        { "answer" => "The LLM returned an empty response.", "citations" => [] }
      end
    rescue JSON::ParserError
      { "answer" => "The LLM returned invalid JSON.", "citations" => [], "raw_response" => json_response_text }
    rescue => e
      Rails.logger.error "GroundingService: Error during LLM call: #{e.class} - #{e.message}"
      { "answer" => "An error occurred while communicating with the LLM. Error: #{e.class} - #{e.message}", "citations" => [] }
    end
  end

  def transform_query(question)
    system_prompt = <<~PROMPT
You are an expert search query creator. Your task is to transform the user's question into an optimal, specific search engine query.
The goal is to produce a query that will retrieve the most relevant documents to answer the user's question.
Your response should be a single JSON object with one key: "search_query".

Example:
User question: "What about scholarships for white women?"
Your response:
{
  "search_query": "scholarships for caucasian women grants for female students eligibility merit-based scholarships not restricted by ethnicity"
}
PROMPT

    user_prompt = "User question: #{question}"

    messages = [
      { role: "system", content: system_prompt.strip },
      { role: "user", content: user_prompt }
    ]

    begin
      response = @llm_client.chat(
        parameters: {
          model: LLM_MODEL_NAME,
          messages: messages,
          temperature: 0.1,
          response_format: { type: "json_object" }
        }
      )
      
      json_response_text = response.dig("choices", 0, "message", "content")&.strip
      
      if json_response_text
        JSON.parse(json_response_text)["search_query"]
      else
        question # Fallback to original question
      end
    rescue JSON::ParserError, NoMethodError
      question # Fallback to original question
    rescue => e
      Rails.logger.error "GroundingService: Error during query transformation: #{e.class} - #{e.message}"
      question # Fallback to original question
    end
  end
end
