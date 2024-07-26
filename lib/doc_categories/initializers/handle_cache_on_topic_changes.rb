# frozen_string_literal: true

module ::DocCategories
  module Initializers
    # since the index structure is serialized into the category data, we need to invalidate the site cache when
    # an index topic changes category or is deleted

    class HandleCacheOnTopicChanges < Initializer
      def apply
        plugin.add_class_method(:topic, :clear_doc_categories_cache) { Site.clear_cache }

        # `previous_changes` is not returning any data on the after_commit hook
        # to workaround this, we stash the data we need to be used in the after_commit hook
        plugin.add_model_callback(:topic, :after_save) do
          return unless saved_change_to_category_id?

          # we're only interested if the topic changed categories or the delete status was changed
          @doc_categories_invalidation_data = { category_id: saved_change_to_category_id }
        end

        plugin.add_model_callback(:topic, :after_commit) do
          return unless @doc_categories_invalidation_data

          # check if the topic id matches, if available, the current or old category index topic id
          index_topic_id = category&.doc_index_topic_id
          publish_category = index_topic_id.present? && index_topic_id == id
          publish_old_category =
            if @doc_categories_invalidation_data[:category_id].present? &&
                 old_category_id = @doc_categories_invalidation_data[:category_id][0]
              old_category = Category.find_by(id: old_category_id)

              old_category_index_topic_id = old_category&.doc_index_topic_id
              old_category_index_topic_id.present? && old_category_index_topic_id == id
            end

          @doc_categories_invalidation_data = nil

          self.class.clear_doc_categories_cache if publish_category || publish_old_category
          category&.publish_category if publish_category
          old_category&.publish_category if publish_old_category
        end

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
