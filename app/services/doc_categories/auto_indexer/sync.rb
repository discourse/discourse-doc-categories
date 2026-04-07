# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class Sync
      include Service::Base

      MAX_LINKS_PER_SECTION = DocCategories::Index::MAX_LINKS_PER_SECTION

      params do
        attribute :index_id, :integer

        validates :index_id, presence: true
      end

      model :index
      policy :has_auto_index_section
      step :fetch_qualifying_topic_ids
      step :compute_diff

      transaction do
        step :add_missing_topics
        step :remove_stale_topics
      end

      step :publish_changes

      private

      def fetch_index(params:)
        DocCategories::Index.find_by(id: params.index_id)
      end

      def has_auto_index_section(index:)
        context[:auto_index_section] = index.auto_index_section
        context[:auto_index_section].present?
      end

      def fetch_qualifying_topic_ids(index:)
        context[:qualifying_topic_ids] = ::Topic
          .where(category_id: index.matching_category_ids)
          .where(visible: true)
          .where(archetype: Archetype.default)
          .where(deleted_at: nil)
          .pluck(:id)
          .to_set
      end

      def compute_diff(index:, qualifying_topic_ids:)
        existing_linked_topic_ids =
          DocCategories::SidebarLink
            .joins(:sidebar_section)
            .where(sidebar_section: { index_id: index.id })
            .where.not(topic_id: nil)
            .pluck(:topic_id)
            .to_set

        context[:topics_to_add] = (qualifying_topic_ids - existing_linked_topic_ids).to_a
        context[:topics_to_remove] = DocCategories::SidebarLink
          .auto_indexed
          .joins(:sidebar_section)
          .where(sidebar_section: { index_id: index.id })
          .where.not(topic_id: qualifying_topic_ids.to_a)
          .pluck(:id)
      end

      def add_missing_topics(auto_index_section:, topics_to_add:)
        current_max = auto_index_section.sidebar_links.maximum(:position) || -1
        available_slots = MAX_LINKS_PER_SECTION - auto_index_section.sidebar_links.count

        topics_to_add
          .first(available_slots)
          .each_with_index do |topic_id, idx|
            topic = ::Topic.find_by(id: topic_id)
            next if topic.nil?

            auto_index_section.sidebar_links.create!(
              topic_id: topic.id,
              href: topic.relative_url,
              position: current_max + idx + 1,
              auto_indexed: true,
            )
          end
      end

      def remove_stale_topics(topics_to_remove:)
        if topics_to_remove.present?
          DocCategories::SidebarLink.where(id: topics_to_remove).destroy_all
        end
      end

      def publish_changes(index:)
        Site.clear_cache
        index.category.publish_category
      end
    end
  end
end
