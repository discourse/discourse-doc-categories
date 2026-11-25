# frozen_string_literal: true

module DocCategories
  module AutoIndexer
    class RemoveTopic
      include Service::Base

      params do
        attribute :topic_id, :integer

        validates :topic_id, presence: true
      end

      transaction do
        model :locked_category_ids, :lock_categories, optional: true
        model :auto_indexed_links, optional: true
        model :affected_categories, optional: true
        step :destroy_links
      end

      only_if(:categories_changed) { step :publish_changes }

      private

      def lock_categories(params:)
        category_ids =
          SidebarLink
            .auto_indexed_for_topic(params.topic_id)
            .distinct
            .pluck("doc_categories_indexes.category_id")
        Index.lock_categories(category_ids)
      end

      def fetch_auto_indexed_links(params:, locked_category_ids:)
        SidebarLink
          .auto_indexed_for_topic(params.topic_id)
          .where(doc_categories_indexes: { category_id: locked_category_ids })
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
        DocCategories::Action::PublishSidebarChanges.call(
          category_ids: affected_categories.map(&:id),
        )
      end
    end
  end
end
