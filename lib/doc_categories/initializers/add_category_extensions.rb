# frozen_string_literal: true

module ::DocCategories
  module Initializers
    module CategoryExtension
      def self.prepended(base)
        base.has_one :doc_categories_index,
                     class_name: "DocCategories::Index",
                     foreign_key: :category_id,
                     dependent: :destroy
      end
    end

    class AddCategoryExtensions < Initializer
      def apply
        Category.prepend CategoryExtension

        plugin.add_class_method(:category, :doc_category_ids) do
          CategoryCustomField
            .where(name: DocCategories::CATEGORY_INDEX_TOPIC)
            .where.not(value: nil)
            .pluck(:category_id)
        end

        plugin.add_to_class(:category, :doc_category?) { doc_index_topic_id.present? }

        plugin.add_to_class(:category, :doc_index_topic_id) do
          custom_fields[DocCategories::CATEGORY_INDEX_TOPIC]
        end
      end
    end
  end
end
