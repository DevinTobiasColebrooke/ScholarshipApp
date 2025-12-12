# Project Overview

This is a Ruby on Rails application designed to help users find and research scholarship-granting organizations. It leverages data from IRS 990-PF filings to identify private foundations that may offer scholarships. The application provides a comprehensive search interface with both structured and semantic search capabilities.

## Key Technologies

*   **Backend:** Ruby on Rails 8
*   **Database:** PostgreSQL with `pgvector` for semantic search and `pg_search` for full-text search.
*   **Frontend:** Hotwire (Turbo, Stimulus) and Tailwind CSS.
*   **Deployment:** Docker with Kamal.
*   **Key Gems:**
    *   `pgvector` & `neighbor`: For vector similarity search on organization embeddings.
    *   `pg_search`: For full-text search on organization and grant data.
    *   `nokogiri`: For parsing XML data from IRS 990-PF filings.
    *   `pagy`: For pagination.
    *   `kamal`: For deployment.

## Architecture

The application is centered around the `Organization` model, which stores information about each foundation. The `OrganizationSearchService` is the core of the search functionality, providing a flexible way to filter and search for organizations based on various criteria. The `EmbeddingService` is used to generate embeddings from organization data, which are then used for semantic search.

The application's UI is built with Hotwire and Tailwind CSS, providing a modern and responsive user experience.

# Building and Running

## Prerequisites

*   Ruby
*   PostgreSQL with the `pgvector` extension enabled.
*   Node.js and yarn.

## Setup

1.  **Install dependencies:**
    ```bash
    bundle install
    yarn install
    ```

2.  **Create the database:**
    ```bash
    rails db:create
    ```

3.  **Run migrations:**
    ```bash
    rails db:migrate
    ```

4.  **Seed the database (if applicable):**
    ```bash
    rails db:seed
    ```

## Running the application

```bash
bin/dev
```

## Running tests

```bash
rails test
```

# Development Conventions

*   **Styling:** The project uses `rubocop-rails-omakase` for Ruby code styling.
*   **Testing:** The project uses the default Rails testing framework (Minitest).
*   **Search:** The `OrganizationSearchService` should be used for all organization searches. New search filters should be added to this service.
*   **Embeddings:** The `EmbeddingService` is used to generate embeddings for semantic search. The `to_embeddable_text` method on the `Organization` model defines the text that is used to create the embedding.

## Additional Documentation

Detailed documentation for agent flow, local LLM implementation, email outreach planning, and Google Search grounding can be found in the `docs/` directory.

## Google Gemini Integration

The application uses the Google Gemini API to populate email addresses for organizations.

*   **`GoogleGeminiService`:** The `app/services/google_gemini_service.rb` handles communication with the Google Gemini API.
*   **Rake Task:** A rake task `populate_emails_with_gemini` in `lib/tasks/populate_emails_with_gemini.rake` uses the `GoogleGeminiService` to find and update missing email addresses for organizations.
*   **Documentation:** Further details on the implementation can be found in `docs/implement_google_search/how_google_api_was_implemented.md`.
