# frozen_string_literal: true

module DocCategories
  module Initializers
    class HandleIndexVisibility < Initializer
      def apply
        refresh_handler = method(:refresh_indexes_for_topics)
        sync_handler = method(:sync_auto_indexes)

        plugin.add_model_callback(:topic, :after_update) do
          next unless saved_change_to_category_id? || saved_change_to_archetype?

          topic_id = id
          category_ids = saved_change_to_category_id || [category_id]
          DB.after_commit do
            refresh_handler.call(::Topic.with_deleted.where(id: topic_id))
            sync_handler.call(category_ids)
          end
        end

        plugin.on(:category_updated) do |category|
          next unless category.saved_change_to_read_restricted?

          refresh_indexes_for_topics(::Topic.with_deleted.where(category_id: category.id))
          sync_auto_indexes([category.id])
        end
      end

      private

      def sync_auto_indexes(category_ids)
        category_ids = category_ids.compact
        ancestor_ids = category_ids.dup
        category_ids.each do |category_id|
          parent_id = ::Category.where(id: category_id).pick(:parent_category_id)
          while parent_id
            ancestor_ids << parent_id
            parent_id = ::Category.where(id: parent_id).pick(:parent_category_id)
          end
        end

        DocCategories::Index
          .joins(:sidebar_sections)
          .where(
            category_id: ancestor_ids.uniq,
            index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
          )
          .where(sidebar_sections: { auto_index: true })
          .distinct
          .each do |index|
            unless index.auto_index_include_subcategories ||
                     category_ids.include?(index.category_id)
              next
            end

            ::Jobs.enqueue(:doc_categories_auto_index, action: "sync", index_id: index.id)
          end
      end

      def refresh_indexes_for_topics(topics)
        categories =
          ::Category
            .joins(doc_categories_index: { sidebar_sections: :sidebar_links })
            .where(doc_categories_sidebar_links: { topic_id: topics.select(:id) })
            .distinct
            .to_a
        return if categories.empty?

        Site.clear_cache
        Site.clear_anon_cache!
        categories.each(&:publish_category)
      end
    end
  end
end
