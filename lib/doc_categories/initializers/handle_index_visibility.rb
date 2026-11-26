# frozen_string_literal: true

module DocCategories
  module Initializers
    class HandleIndexVisibility < Initializer
      def apply
        refresh_handler = method(:refresh_indexes_for_topics)
        sync_handler = method(:sync_auto_indexes)

        plugin.add_model_callback(:topic, :after_update) do
          category_or_archetype_changed = saved_change_to_category_id? || saved_change_to_archetype?
          unless category_or_archetype_changed || saved_change_to_visible? ||
                   saved_change_to_deleted_at?
            next
          end

          topic_id = id
          category_ids = saved_change_to_category_id || [category_id]
          DB.after_commit do
            refresh_handler.call([topic_id])
            sync_handler.call(category_ids) if category_or_archetype_changed
          end
        end

        plugin.add_model_callback(:shared_draft, :after_create) do
          draft_topic_id = topic_id
          DB.after_commit { refresh_handler.call([draft_topic_id]) }
        end

        plugin.on(:topic_published) do |topic|
          DB.after_commit { refresh_indexes_for_topics([topic.id]) }
        end

        plugin.on(:category_updated) do |category|
          next unless category.saved_change_to_read_restricted?

          refresh_indexes_for_topics(
            ::Topic.with_deleted.where(category_id: category.id).pluck(:id),
          )
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

      def refresh_indexes_for_topics(topic_ids)
        links = DocCategories::SidebarLink.targeting_topics(topic_ids)
        linked_indexes = Index.joins(sidebar_sections: :sidebar_links).merge(links).select(:id)
        indexes = Index.where(id: linked_indexes).or(Index.where(index_topic_id: topic_ids))
        categories = ::Category.where(id: indexes.select(:category_id)).to_a
        return if categories.empty?

        Site.clear_cache
        Site.clear_anon_cache!
        categories.each(&:publish_category)
      end
    end
  end
end
