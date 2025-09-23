# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleTopicChanges < Initializer
      def apply
        plugin.add_class_method(:topic, :clear_doc_categories_cache) { Site.clear_cache }

        plugin.on(:topic_trashed) { |topic| handle_topic_trashed(topic) }

        plugin.on(:topic_recovered) { |topic| handle_topic_recovered(topic) }
      end

      private

      def handle_topic_trashed(topic)
        index = DocCategories::Index.find_by(index_topic_id: topic.id)
        return if !index

        category = index.category
        return if !category

        DocCategories::CategoryIndexManager.new(category).assign!(nil)
      end

      def handle_topic_recovered(topic)
        category = topic.category
        return if !category

        existing_index = DocCategories::Index.find_by(category_id: category.id)

        return if existing_index.present? && existing_index.index_topic_id != topic.id

        if existing_index&.index_topic_id == topic.id
          enqueue_refresh(category.id)
        elsif existing_index.nil?
          DocCategories::CategoryIndexManager.new(category).assign!(topic.id)
        else
          return
        end
      end

      def enqueue_refresh(category_id)
        ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category_id)
      end
    end
  end
end
