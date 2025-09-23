# frozen_string_literal: true

Fabricator(:doc_categories_sidebar_link, class_name: "DocCategories::SidebarLink") do
  sidebar_section { Fabricate(:doc_categories_sidebar_section) }
  title { sequence(:title) { |n| "Link Title #{n}" } }
  href do |attrs|
    category = attrs[:sidebar_section].index.category
    category ? Fabricate(:topic, category:) : "https://example.com/#{SecureRandom.hex(4)}"
  end
  position { sequence(:position) { |n| n } }
end
