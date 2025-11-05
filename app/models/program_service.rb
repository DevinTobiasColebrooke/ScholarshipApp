class ProgramService < ApplicationRecord
  belongs_to :organization

  scope :search_description_text, ->(query) {
    where("description_txt ILIKE ?", "%#{query}%")
  }
end
