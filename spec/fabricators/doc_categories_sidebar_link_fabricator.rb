# frozen_string_literal: true

Fabricator(:doc_categories_sidebar_section, class_name: "DocCategories::SidebarSection") do
  index { Fabricate(:doc_categories_index) }
  title { sequence(:title) { |n| "Section Title #{n}" } }
  position { sequence(:position) { |n| n } }
end
