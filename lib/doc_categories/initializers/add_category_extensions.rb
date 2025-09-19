# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class AddCategoryExtensions < Initializer
      def apply
        plugin.add_class_method(:category, :doc_category_ids) do
          DocCategories::Index.distinct.pluck(:category_id)
        end

        plugin.add_to_class(:category, :doc_category?) { doc_categories_index.present? }

        plugin.add_to_class(:category, :doc_index_topic_id) { doc_categories_index&.index_topic_id }

        plugin.add_to_class(:category, :doc_index_topic_id=) do |value|
          normalized = value.present? ? value.to_i : nil
          category = self

          ::DB.after_commit do
            DocCategories::CategoryIndexManager.new(category).assign!(normalized)
          end
        end

        plugin.on(:category_updated) do |category|
          next unless SiteSetting.doc_categories_enabled

          category.reload if DocCategories::Index.exists?(category_id: category.id)
        end
      end
    end
  end
end
