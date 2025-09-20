# frozen_string_literal: true

module ::DocCategories
  module Initializers
    # since the index structure is serialized into the category data, we need to invalidate the site cache when
    # an index topic changes category or is deleted

    class HandleTopicChanges < Initializer
      def apply
        plugin.add_class_method(:topic, :clear_doc_categories_cache) { Site.clear_cache }

        plugin.on(:topic_trashed) do |topic|
          Topic.clear_doc_categories_cache if topic.category&.doc_index_topic_id == topic.id
          topic.category&.publish_category
        end

        plugin.on(:topic_recovered) do |topic|
          Topic.clear_doc_categories_cache if topic.category&.doc_index_topic_id == topic.id
          topic.category&.publish_category
        end
      end
    end
  end
end
