# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class Sync
      include Service::Base

      params do
        attribute :index_id, :integer

        validates :index_id, presence: true
      end

      model :index
      model :auto_index_section
      model :topics_to_add, optional: true
      model :stale_links, optional: true

      transaction do
        step :remove_stale_links
        model :added_links, :add_missing_topics, optional: true
      end

      only_if(:index_changed) { step :publish_changes }

      private

      def fetch_index(params:)
        DocCategories::Index.find_by(id: params.index_id)
      end

      def fetch_auto_index_section(index:)
        index.auto_index_section
      end

      def fetch_topics_to_add(index:)
        existing_topic_ids =
          DocCategories::SidebarLink
            .joins(:sidebar_section)
            .where(sidebar_section: { index_id: index.id })
            .where.not(topic_id: nil)
            .select(:topic_id)

        ::Topic
          .where(category_id: index.matching_category_ids)
          .where(visible: true, archetype: Archetype.default, deleted_at: nil)
          .where.not(id: existing_topic_ids)
          .order(created_at: :desc)
          .limit(DocCategories::Index::MAX_LINKS_PER_SECTION)
          .to_a
      end

      def fetch_stale_links(index:)
        DocCategories::SidebarLink
          .auto_indexed
          .joins(:sidebar_section)
          .where(sidebar_section: { index_id: index.id })
          .joins("LEFT JOIN topics ON topics.id = doc_categories_sidebar_links.topic_id")
          .where(<<~SQL, Archetype.default, index.matching_category_ids)
            topics.id IS NULL
            OR topics.deleted_at IS NOT NULL
            OR topics.visible = false
            OR topics.archetype != ?
            OR topics.category_id NOT IN (?)
          SQL
          .to_a
      end

      def add_missing_topics(auto_index_section:, topics_to_add:)
        current_max = auto_index_section.sidebar_links.maximum(:position) || -1
        available_slots = [
          DocCategories::Index::MAX_LINKS_PER_SECTION - auto_index_section.sidebar_links.count,
          0,
        ].max

        topics_to_add
          .first(available_slots)
          .each_with_index
          .map do |topic, idx|
            auto_index_section.sidebar_links.create!(
              topic_id: topic.id,
              href: topic.relative_url,
              position: current_max + idx + 1,
              auto_indexed: true,
            )
          end
      end

      def remove_stale_links(stale_links:)
        DocCategories::SidebarLink.where(id: stale_links.map(&:id)).delete_all
      end

      def index_changed(added_links:, stale_links:)
        added_links.present? || stale_links.present?
      end

      def publish_changes(index:)
        Site.clear_cache
        index.category.publish_category
      end
    end
  end
end
