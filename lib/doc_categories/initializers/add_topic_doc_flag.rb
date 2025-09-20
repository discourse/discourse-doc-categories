# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class AddTopicDocFlag < Initializer
      def apply
        plugin.add_to_serializer(
          :topic_view,
          :doc_topic,
          include_condition: -> do
            SiteSetting.doc_categories_enabled && object.topic.category&.doc_category?
          end,
        ) { true }
      end
    end
  end
end
