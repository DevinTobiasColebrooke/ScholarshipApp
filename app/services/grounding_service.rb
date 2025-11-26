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
2.  If the context does not contain the answer, state that you cannot answer the question from the provided information.
3.  Your response must be a single JSON object with two keys: "answer" and "citations".
4.  The "answer" key should contain the plain text answer to the question.
5.  The "citations" key should be an array of objects, where each object has two keys: "source_url" and "text". The "text" should be the exact sentence or phrase from the context that supports your answer.

Example response format:
{
  "answer": "The capital of France is Paris, which is also its most populous city.",
  "citations": [
    { "source_url": "https://en.wikipedia.org/wiki/Paris", "text": "Paris is the capital and most populous city of France." }
  ]
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
end
