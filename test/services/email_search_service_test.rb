require "test_helper"
require "minitest/mock" # Ensure Minitest::Mock is available

class EmailSearchServiceTest < ActiveSupport::TestCase
  # Reset model index and rate limiter before each test
  setup do
    EmailSearchService.class_variable_set(:@@current_model_index, 0)
    EmailSearchService.class_variable_set(:@@last_request_time, Time.at(0))

    @matching_organization = Organization.create!(
      name: "Test Org for Email Search (Matching Profile)",
      website_address_txt: "https://example.com/matching",
      is_scholarship_funder: true,
      restrictions_on_awards_txt: "Scholarships for all students."
    )
  end

  test "should find email for a matching organization" do
    organization = @matching_organization

    mock_gemini_response(status: 200, body: {
      candidates: [{
        content: {
          parts: [{ text: "contact@example.com" }]
        }
      }]
    }.to_json) do
      email = EmailSearchService.new(organization).find_email
      assert_equal "contact@example.com", email
    end
  end

  private

  # Helper to mock a single Gemini API response
  def mock_gemini_response(status:, body:)
    Faraday.stub(:post, ->(url, req_body, headers) {
      response = Minitest::Mock.new
      response.expect(:status, status)
      response.expect(:success?, status == 200)
      response.expect(:body, body)
      response
    }) do
      yield if block_given?
    end
  end
end
