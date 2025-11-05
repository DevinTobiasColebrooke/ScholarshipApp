class Grant < ApplicationRecord
  belongs_to :organization

  scope :search_purpose_text, ->(query) {
    where("purpose_text ILIKE :q", q: "%#{query}%")
  }

  def recipient_organization
    Rails.logger.warn "DEPRECATED: Grant#recipient_organization called. Use pre-loaded map instead."
    return nil unless recipient_business_name.present?

    cleaned_name = self.recipient_business_name.to_s.upcase.strip
    Organization.find_by("UPPER(name) = ?", cleaned_name)
  end
end
