# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleTopicEvents < Initializer
      def apply
        plugin.on(:topic_trashed) { |topic| refresh_for_topic(topic) }

        plugin.on(:topic_recovered) { |topic| refresh_for_topic(topic) }
      end

      private

      def refresh_for_topic(topic)
        return unless SiteSetting.doc_categories_enabled
        return if topic.blank?

        if (index = DocCategories::Index.find_by(index_topic_id: topic.id))
          ::Jobs.enqueue(:doc_categories_refresh_index, category_id: index.category_id)
        end
      end
    end
  end
end
