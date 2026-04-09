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
      step :compute_topics_to_add
      step :find_stale_links

      transaction do
        step :add_missing_topics
        step :remove_stale_links
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

      def compute_topics_to_add(index:)
        existing_topic_ids =
          DocCategories::SidebarLink
            .joins(:sidebar_section)
            .where(sidebar_section: { index_id: index.id })
            .where.not(topic_id: nil)
            .select(:topic_id)

        context[:topics_to_add] = ::Topic
          .where(category_id: index.matching_category_ids)
          .where(visible: true, archetype: Archetype.default, deleted_at: nil)
          .where.not(id: existing_topic_ids)
          .order(created_at: :desc)
          .limit(MAX_LINKS_PER_SECTION)
          .pluck(:id)
      end

      def find_stale_links(index:)
        context[:stale_link_ids] = DocCategories::SidebarLink
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

      def remove_stale_links(stale_link_ids:)
        DocCategories::SidebarLink.where(id: stale_link_ids).destroy_all if stale_link_ids.present?
      end

      def publish_changes(index:)
        Site.clear_cache
        index.category.publish_category
      end
    end
  end
end
