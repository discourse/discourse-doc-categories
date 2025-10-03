# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleTopicBump < Initializer
      def apply
        plugin.register_modifier(
          :should_bump_topic,
        ) do |should_bump, post, post_changes, topic_changes, editor|
          if post.topic.category&.doc_category? && post.is_first_post? && post_changes.any?
            next true
          end
        end
      end
    end
  end
end
