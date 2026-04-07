# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleAutoIndex < Initializer
      def apply
        plugin.on(:topic_created) { |topic, _opts, _user| enqueue_add(topic) }
        plugin.on(:topic_recovered) { |topic| enqueue_add(topic) }
        plugin.on(:topic_trashed) { |topic| enqueue_remove(topic) }
        plugin.on(:topic_destroyed) { |topic, _user| enqueue_remove(topic) }
      end

      private

      def enqueue_add(topic)
        return if !topic&.category_id
        return if !has_auto_index_for_category?(topic.category_id)

        ::Jobs.enqueue(:doc_categories_auto_index, action: "add", topic_id: topic.id)
      end

      def enqueue_remove(topic)
        return if !topic
        ::Jobs.enqueue(:doc_categories_auto_index, action: "remove", topic_id: topic.id)
      end

      def has_auto_index_for_category?(category_id)
        DocCategories::Index
          .joins(:sidebar_sections)
          .where(
            index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
            sidebar_sections: {
              auto_index: true,
            },
          )
          .exists?
      end
    end
  end
end
