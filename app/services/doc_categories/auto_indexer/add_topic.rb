# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class AddTopic
      include Service::Base

      MAX_LINKS_PER_SECTION = DocCategories::Index::MAX_LINKS_PER_SECTION

      params do
        attribute :topic_id, :integer

        validates :topic_id, presence: true
      end

      model :topic
      policy :topic_qualifies
      step :find_matching_indexes

      transaction { step :create_links }

      step :publish_changes

      private

      def fetch_topic(params:)
        ::Topic.find_by(id: params.topic_id)
      end

      def topic_qualifies(topic:)
        !topic.trashed? && topic.visible? && topic.archetype == Archetype.default
      end

      def find_matching_indexes(topic:)
        context[:matching_indexes] = DocCategories::Index
          .joins(:sidebar_sections)
          .where(sidebar_sections: { auto_index: true })
          .where(index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT)
          .distinct
          .select { |index| index.matching_category_ids.include?(topic.category_id) }
      end

      def create_links(matching_indexes:, topic:)
        context[:affected_indexes] = []

        matching_indexes.each do |index|
          section = index.auto_index_section
          next if section.nil?
          next if topic_already_linked?(index, topic)
          next if section.sidebar_links.count >= MAX_LINKS_PER_SECTION

          next_position = (section.sidebar_links.maximum(:position) || -1) + 1
          section.sidebar_links.create!(
            topic_id: topic.id,
            href: topic.relative_url,
            position: next_position,
            auto_indexed: true,
          )
          context[:affected_indexes] << index
        end
      end

      def publish_changes(affected_indexes:)
        return if affected_indexes.blank?

        Site.clear_cache
        affected_indexes.each { |index| index.category.publish_category }
      end

      def topic_already_linked?(index, topic)
        DocCategories::SidebarLink
          .joins(:sidebar_section)
          .where(sidebar_section: { index_id: index.id })
          .exists?(topic_id: topic.id)
      end
    end
  end
end
