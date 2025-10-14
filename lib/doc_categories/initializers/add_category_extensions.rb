# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class AddCategoryExtensions < Initializer
      def apply
        plugin.add_class_method(:category, :doc_category_ids) do
          DocCategories::Index.pluck(:category_id)
        end

        plugin.add_to_class(:category, :doc_category?) { doc_categories_index.present? }

        plugin.add_to_class(:category, :doc_index_topic_id) { doc_categories_index&.index_topic_id }

        plugin.add_to_serializer(:basic_category, :doc_index_topic_id) do
          object&.doc_categories_index&.index_topic_id
        end

        plugin.register_category_update_param_with_callback(
          :doc_index_topic_id,
        ) { |category, value| DocCategories::CategoryIndexManager.new(category).assign!(value) }
      end
    end
  end
end
