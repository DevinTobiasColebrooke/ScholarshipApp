# app/models/web_document.rb
class WebDocument < ApplicationRecord
  # Add pgvector support via neighbor gem
  has_neighbors :embedding
end
