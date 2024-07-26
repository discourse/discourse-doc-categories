# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleCacheOnPostChanges < Initializer
      def apply
        # since the index structure is serialized into the category data, we need to invalidate the site cache when
        # the first post of an index topic is updated
        plugin.add_class_method(:post, :clear_doc_categories_cache) { Site.clear_cache }

        plugin.add_model_callback(:post, :after_commit) do
          return unless is_first_post?
          return if previous_changes[:cooked].blank?
          return if (category = topic.category).blank?
          return if (index_topic_id = category.doc_index_topic_id).blank?
          return if topic_id != index_topic_id

          self.class.clear_doc_categories_cache
          category.publish_category
        end
      end
    end
  end
end
