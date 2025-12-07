module ApplicationHelper
  include ActionView::Helpers::NumberHelper

  def tooltip(text)
    content_tag(:span, "?", class: "ml-2 inline-flex items-center justify-center h-4 w-4 rounded-full bg-gray-300 text-gray-700 text-xs font-bold cursor-help", title: text)
  end
end
