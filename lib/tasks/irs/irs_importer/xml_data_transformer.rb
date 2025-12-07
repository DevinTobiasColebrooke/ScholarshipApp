require "nokogiri"
require "bigdecimal"
require "date"

module IrsImporter
module XmlDataTransformer
private

# Helper to convert a simple tag name into a namespace-agnostic XPath segment.
# This method is designed to only convert actual tag names.
def transform_xpath_segment(segment)
  return segment if segment.blank? || segment == "." || segment.start_with?("*") || segment.start_with?("@")

  # Check if the segment looks like a tag name or an element with an index/predicate
  if segment.match?(/^[a-zA-Z]/)
    # Check if it has a predicate (e.g., element[1])
    if segment.include?("[")
      tag, predicate = segment.match(/^(\w+)\[(.*)\]$/)&.captures
      if tag.present? && !tag.include?(":")
        return "*[local-name()='#{tag}'][#{predicate}]"
      end
    end

    # Simple tag name (no prefix, no predicate)
    return "*[local-name()='#{segment}']" if !segment.include?(":")
  end

  segment # Return original if complex, namespaced, or untransformable
end

# Primary helper to find a single node using namespace-agnostic XPath
def extract_node(xpath, context_node = nil)
  context = context_node || @doc

  # Safely handle leading // or / in the xpath by preserving them in the prefix
  prefix = ""
  path_segments = []

  if xpath.start_with?("//")
    prefix = "//"
    path_segments = xpath[2..-1].split("/")
  elsif xpath.start_with?("/")
    prefix = "/"
    path_segments = xpath[1..-1].split("/")
  else
    # Relative path starting with a tag name or local search path
    path_segments = xpath.split("/")
  end

  # Filter out potential empty strings resulting from the split
  path_segments.reject!(&:empty?)

  # Transform only the tag segments
  transformed_segments = path_segments.map do |segment|
    transform_xpath_segment(segment)
  end

  transformed_xpath = prefix + transformed_segments.join("/")

  # Nokogiri's at_xpath handles the path resolution after transformation
  context.at_xpath(transformed_xpath)
rescue Nokogiri::XML::XPath::SyntaxError => e
  # Log the malformed XPath for debugging
  Rails.logger.error "XPath Error: #{e.message} using query: #{transformed_xpath} (Original: #{xpath})"
  nil
end

# Primary helper to find multiple nodes using namespace-agnostic XPath
def extract_nodes(xpath)
  # Safely handle leading // or / in the xpath by preserving them in the prefix
  prefix = ""
  path_segments = []

  if xpath.start_with?("//")
    prefix = "//"
    path_segments = xpath[2..-1].split("/")
  elsif xpath.start_with?("/")
    prefix = "/"
    path_segments = xpath[1..-1].split("/")
  else
    path_segments = xpath.split("/")
  end

  path_segments.reject!(&:empty?)

  transformed_segments = path_segments.map do |segment|
    transform_xpath_segment(segment)
  end

  transformed_xpath = prefix + transformed_segments.join("/")

  @doc.xpath(transformed_xpath)
rescue Nokogiri::XML::XPath::SyntaxError => e
  Rails.logger.error "XPath Error: #{e.message} using query: #{transformed_xpath} (Original: #{xpath})"
  [] # Return empty array on failure
end


def extract_text(xpath, context_node = nil)
  extract_node(xpath, context_node)&.text
end

def extract_decimal(xpath, context_node = nil)
  text = extract_text(xpath, context_node)
  text.present? ? text.to_d : nil
rescue StandardError
  nil
end

def extract_date(xpath)
  text = extract_text(xpath)
  text.present? ? Date.parse(text) : nil
rescue StandardError
  nil
end

# Helper to construct a cleaned US address string from an XML node structure.
def extract_us_address(parent_node)
  # Look up address nodes using explicit namespace-agnostic relative XPath
  address_node = parent_node.at_xpath('.//*[local-name()="RecipientUSAddress"]') || parent_node.at_xpath('.//*[local-name()="USAddress"]')
  return nil unless address_node

  # Now use Nokogiri's standard at_xpath/local-name for internal tags
  address_line1 = address_node.at_xpath("*[local-name()='AddressLine1Txt']")&.text
  address_line2 = address_node.at_xpath("*[local-name()='AddressLine2Txt']")&.text
  city = address_node.at_xpath("*[local-name()='CityNm']")&.text

  state = address_node.at_xpath("*[local-name()='StateAbbreviationCd']")&.text
  state ||= address_node.at_xpath("*[local-name()='StateCd']")&.text # Fallback state code

  zip = address_node.at_xpath("*[local-name()='ZIPCd']")&.text

  parts = [ address_line1, address_line2 ].compact
  city_state_zip = [ city, state, zip ].compact.join(" ")

  parts << city_state_zip if city_state_zip.present?

  parts.join("\n").strip.presence
end
end
end
