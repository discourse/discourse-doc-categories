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
        ) do |category, value|
          DocCategories::CategoryIndexManager.call(
            params: {
              category_id: category.id,
              topic_id: value,
            },
          )
        end

        plugin.register_category_update_param_with_callback(
          :doc_index_sections,
        ) do |category, value|
          begin
            sections = value.present? ? JSON.parse(value) : nil
          rescue JSON::ParserError
            raise Discourse::InvalidParameters.new(:doc_index_sections)
          end

          if sections.present? && !sections.is_a?(::Array)
            raise Discourse::InvalidParameters.new(:doc_index_sections)
          end

          # Gate: require the index editor setting unless the category is already in direct mode
          if !SiteSetting.doc_categories_index_editor && sections.present?
            index = DocCategories::Index.find_by(category_id: category.id)
            raise Discourse::InvalidAccess if index.nil? || !index.mode_direct?
          end

          result =
            DocCategories::IndexSaver.call(params: { category_id: category.id, sections: sections })

          if result.failure?
            if result["result.policy.not_topic_managed"]&.failure?
              raise Discourse::InvalidAccess
            elsif result["result.step.parse_and_validate_sections"]&.failure?
              raise Discourse::InvalidParameters.new(:doc_index_sections)
            end
          end
        end
      end
    end
  end
end
