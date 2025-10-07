# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandlePostChanges < Initializer
      def apply
        plugin.on(:post_edited) do |post, _, revisor|
          topic = post.topic
          category = topic&.category

          if doc_index_topic_post_cooked_changed?(topic, category, post, revisor)
            enqueue_refresh(category.id)
            next
          end

          handle_category_change(topic, category, revisor)
        end
      end

      private

      def doc_index_topic_post_cooked_changed?(topic, category, post, revisor)
        post.is_first_post? && revisor.post_changes[:cooked].present? &&
          doc_index_topic?(topic, category)
      end

      def handle_category_change(topic, current_category, revisor)
        return if !revisor.topic_diff.has_key?("category_id")

        prev_id, curr_id = revisor.topic_diff["category_id"]

        # topic is moved into a doc category which it is the index for
        if current_category && curr_id == current_category.id &&
             doc_index_topic?(topic, current_category)
          enqueue_refresh(curr_id)
          return
        end

        # topic is moved out of a doc category which it is the index for
        prev_category = Category.find_by(id: prev_id)
        enqueue_refresh(prev_id) if prev_category && doc_index_topic?(topic, prev_category)
      end

      def doc_index_topic?(topic, category)
        category&.doc_index_topic_id == topic&.id
      end

      def enqueue_refresh(category_id)
        ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category_id)
      end
    end
  end
end
