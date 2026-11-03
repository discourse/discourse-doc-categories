# frozen_string_literal: true

module DocCategories
  module Initializers
    class HandleIndexVisibility < Initializer
      def apply
        refresh_handler = method(:refresh_indexes_for_topics)

        plugin.add_model_callback(:topic, :after_update) do
          next unless saved_change_to_category_id? || saved_change_to_archetype?

          topic_id = id
          DB.after_commit { refresh_handler.call(::Topic.with_deleted.where(id: topic_id)) }
        end

        plugin.on(:category_updated) do |category|
          next unless category.saved_change_to_read_restricted?

          refresh_indexes_for_topics(::Topic.with_deleted.where(category_id: category.id))
        end
      end

      private

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
