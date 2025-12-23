# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleTopicChanges < Initializer
      def apply
        plugin.add_class_method(:topic, :clear_doc_categories_cache) { Site.clear_cache }

        plugin.on(:topic_trashed) { |topic| handle_topic_trashed(topic) }
      end

      private

      def handle_topic_trashed(topic)
        index = DocCategories::Index.find_by(index_topic_id: topic.id)
        return if !index

        category = index.category
        return if !category

        DocCategories::CategoryIndexManager.new(category).assign!(nil)
      end
    end
  end
end
