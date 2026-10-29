# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class AddTopic
      include Service::Base

      params do
        attribute :topic_id, :integer

        validates :topic_id, presence: true
      end

      model :topic
      policy :topic_qualifies
      model :matching_indexes, optional: true

      transaction { model :affected_indexes, :create_links, optional: true }

      only_if(:indexes_changed) { step :publish_changes }

      private

      def fetch_topic(params:)
        ::Topic.find_by(id: params.topic_id)
      end

      def topic_qualifies(topic:)
        !topic.trashed? && topic.visible? && topic.archetype == Archetype.default
      end

      def fetch_matching_indexes(topic:)
        DocCategories::Index
          .joins(:sidebar_sections)
          .where(sidebar_sections: { auto_index: true })
          .where(index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT)
          .distinct
          .select { |index| index.matching_category_ids.include?(topic.category_id) }
      end

      def create_links(matching_indexes:, topic:)
        matching_indexes.filter_map do |index|
          section = index.auto_index_section
          next if section.nil?
          next if index.sidebar_topic_linked?(topic)
          next if section.sidebar_links.count >= DocCategories::Index::MAX_LINKS_PER_SECTION

          next_position = (section.sidebar_links.maximum(:position) || -1) + 1
          section.sidebar_links.create!(
            topic_id: topic.id,
            href: topic.relative_url,
            position: next_position,
            auto_indexed: true,
          )
          index
        end
      end

      def publish_changes(affected_indexes:)
        Site.clear_cache
        affected_indexes.each { |index| index.category.publish_category }
      end

      def indexes_changed(affected_indexes:)
        affected_indexes.present?
      end
    end
  end
end
