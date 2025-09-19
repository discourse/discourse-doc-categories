# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandlePostEvents < Initializer
      def apply
        plugin.on(:post_edited) do |post, topic_changed, revisor|
          next unless SiteSetting.doc_categories_enabled
          next unless post.is_first_post?

          topic = post.topic
          next if topic.blank?

          refresh_category_ids = []

          if (index = DocCategories::Index.find_by(index_topic_id: topic.id))
            refresh_category_ids << index.category_id
          end

          if topic_changed && revisor.respond_to?(:topic_diff)
            old_category_id = revisor.topic_diff.dig("category_id", 0)
            if old_category_id.present?
              DocCategories::Index.where(
                category_id: old_category_id,
                index_topic_id: topic.id,
              ).destroy_all
              refresh_category_ids << old_category_id
            end
          end

          refresh_category_ids.compact.uniq.each do |category_id|
            ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category_id)
          end
        end
      end
    end
  end
end
