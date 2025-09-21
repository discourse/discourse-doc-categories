# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandlePostChanges < Initializer
      def apply
        # reset cache when
        # - index topic post cooked changes
        # - the category of the topic changes (might change to undefined)
        plugin.on(:post_edited) do |post, _, revisor|
          topic = post.topic
          category = topic&.category

          if doc_index_topic_post_cooked_changed?(topic, category, post, revisor)
            reset_docs_categories([category].compact)
            next
          end

          categories = category_change_involves_doc_category?(topic, category, revisor)
          reset_docs_categories(categories) if categories.present?
        end
      end

      private

      def doc_index_topic_post_cooked_changed?(topic, category, post, revisor)
        post.is_first_post? && revisor.post_changes[:cooked].present? &&
          doc_index_topic?(topic, category)
      end

      def category_change_involves_doc_category?(topic, current_category, revisor)
        return [] unless revisor.topic_diff.has_key?("category_id")

        previous_id, current_id = revisor.topic_diff["category_id"]

        categories = []

        # if topic was index topic but moved out of the category
        previous_category = category_for_id(previous_id, current_category)
        categories << previous_category if doc_index_topic?(topic, previous_category)

        # if topic moved into a category where it is the index topic
        current_category = category_for_id(current_id, current_category)
        categories << current_category if doc_index_topic?(topic, current_category)

        categories.compact.uniq
      end

      def category_for_id(category_id, current_category)
        return nil if category_id.blank?
        return current_category if current_category&.id == category_id

        Category.find_by(id: category_id)
      end

      def doc_index_topic?(topic, category)
        category&.doc_index_topic_id == topic&.id
      end

      def reset_docs_categories(categories)
        # since the index structure is serialized into the category data, we need to invalidate the site cache when the first post of an index topic is updated
        Site.clear_cache
        categories.each { |cat| cat.publish_category }
      end
    end
  end
end
