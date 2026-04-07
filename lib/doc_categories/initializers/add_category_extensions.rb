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

        plugin.register_category_update_param_with_callback(
          :doc_index_sections,
        ) do |category, value|
          begin
            sections = value.present? ? JSON.parse(value) : nil
          rescue JSON::ParserError
            raise Discourse::InvalidParameters.new(:doc_index_sections)
          end

          old_auto_id = category.doc_categories_index&.auto_index_section&.id

          saver = DocCategories::IndexSaver.new(category)
          saver.save_sections!(sections)
          saver.sync_auto_index_if_needed!(sections, old_auto_index_section_id: old_auto_id)
        end
      end
    end
  end
end
