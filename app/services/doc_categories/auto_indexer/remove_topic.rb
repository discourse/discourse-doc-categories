# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class RemoveTopic
      include Service::Base

      params do
        attribute :topic_id, :integer

        validates :topic_id, presence: true
      end

      step :find_auto_indexed_links

      transaction { step :destroy_links }

      step :publish_changes

      private

      def find_auto_indexed_links(params:)
        context[:auto_indexed_links] = DocCategories::SidebarLink
          .auto_indexed
          .joins(sidebar_section: :index)
          .where(topic_id: params.topic_id)
          .includes(sidebar_section: { index: :category })
      end

      def destroy_links(auto_indexed_links:)
        context[:affected_categories] = auto_indexed_links
          .filter_map { |link| link.sidebar_section.index.category }
          .uniq
        auto_indexed_links.destroy_all
      end

      def publish_changes(affected_categories:)
        return if affected_categories.blank?

        Site.clear_cache
        affected_categories.each(&:publish_category)
      end
    end
  end
end
