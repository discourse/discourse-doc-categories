# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class RemoveTopic
      include Service::Base

      params do
        attribute :topic_id, :integer

        validates :topic_id, presence: true
      end

      model :auto_indexed_links, optional: true
      model :affected_categories, optional: true

      transaction { step :destroy_links }

      only_if(:categories_changed) { step :publish_changes }

      private

      def fetch_auto_indexed_links(params:)
        DocCategories::SidebarLink
          .auto_indexed
          .joins(sidebar_section: :index)
          .where(topic_id: params.topic_id)
          .includes(sidebar_section: { index: :category })
      end

      def fetch_affected_categories(auto_indexed_links:)
        auto_indexed_links.filter_map { |link| link.sidebar_section.index.category }.uniq
      end

      def destroy_links(auto_indexed_links:)
        auto_indexed_links.destroy_all
      end

      def categories_changed(affected_categories:)
        affected_categories.present?
      end

      def publish_changes(affected_categories:)
        Site.clear_cache
        affected_categories.each(&:publish_category)
      end
    end
  end
end
