# frozen_string_literal: true

module ::DocCategories
  module PluginInitializers
    module SerializeIndexStructureExtensions
      # since the index structure is serialized into the category data, we need to invalidate the site cache when
      # an index topic changes category or is deleted
      module Topic
        def self.prepended(base)
          base.before_save :doc_categories_stash_invalidation_data
          base.after_commit :doc_categories_invalidate_index
        end

        # this is because `previous_changes` is not returning any data on the after_commit hook
        def doc_categories_stash_invalidation_data
          return unless will_save_change_to_category_id? || will_save_change_to_deleted_at?

          @doc_categories_invalidation_data = {
            category_id: category_id_change_to_be_saved,
            deleted_at: deleted_at_change_to_be_saved,
          }
        end

        def doc_categories_invalidate_index
          return unless @doc_categories_invalidation_data

          # if the either the category or the topic deleted status were changed
          # check if the topic id matches, if available, the current or old category index topic id
          index_topic_id = category&.doc_index_topic_id
          invalidate_cache = index_topic_id.present? && index_topic_id == id
          invalidate_cache ||=
            if @doc_categories_invalidation_data[:category_id].present? &&
                 old_category_id = @doc_categories_invalidation_data[:category_id][0]
              old_category = Category.find_by(id: old_category_id)

              old_category_index_topic_id = old_category&.doc_index_topic_id
              old_category_index_topic_id.present? && old_category_index_topic_id == id
            end

          @doc_categories_invalidation_data = nil
          Site.clear_cache if invalidate_cache
        end
      end

      # since the index structure is serialized into the category data, we need to invalidate the site cache when
      # the first post of an index topic is updated
      module Post
        def self.prepended(base)
          base.after_commit :doc_categories_invalidate_index
        end

        def doc_categories_invalidate_index
          return unless is_first_post?
          return if previous_changes[:cooked].blank?
          return if (category = topic.category).blank?
          return if (index_topic_id = category.doc_index_topic_id).blank?
          return if topic_id != index_topic_id

          Site.clear_cache
        end
      end
    end

    class SerializeIndexStructure < PluginInitializer
      Post.prepend SerializeIndexStructureExtensions::Post
      Topic.prepend SerializeIndexStructureExtensions::Topic

      def apply
        # index structure
        plugin.add_to_serializer(
          :basic_category,
          :doc_category_index,
          include_condition: -> do
            index_topic_id = object.custom_fields[::DocCategories::CATEGORY_INDEX_TOPIC]
            next false if index_topic_id.blank?

            index_topic = Topic.find_by(id: index_topic_id)
            next false if index_topic.blank?

            # ideally we should check if the current user has access to the topic above which would allow securely using
            # topics from any category, but we can't because the categories are serialized on the site serializer
            # without a guardian in scope.
            # as a workaround we force the topic category to match the category serialized, which implies the user has
            # access.
            # NOTICE THAT SUB-CATEGORIES ARE NOT CONSIDERED BECAUSE WE CAN'T CHECK THEIR PERMISSIONS
            next false unless object.id = index_topic.category_id

            first_post = index_topic.first_post
            next false if first_post.blank?

            @doc_category_index = DocCategories::DocIndexTopicParser.new(first_post.cooked).sections
            @doc_category_index.present?
          end,
        ) { @doc_category_index.as_json }
      end
    end
  end
end
