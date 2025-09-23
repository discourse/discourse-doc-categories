# frozen_string_literal: true

Fabricator(:doc_categories_index, class_name: "DocCategories::Index") do
  category { Fabricate(:category_with_definition) }

  after_build do |index, _attrs|
    index.index_topic ||= Fabricate(:topic_with_op, category: index.category)
  end
end
