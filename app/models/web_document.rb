# app/models/web_document.rb
class WebDocument < ApplicationRecord
  # Add pgvector support
  has_vector :embedding, dimensions: 768
end
