# frozen_string_literal: true

module DocCategories
  module Action
    class PublishSidebarChanges < Service::ActionBase
      option :category_ids

      def call
        DB.after_commit do
          Site.clear_cache
          ::Category.where(id: category_ids).each(&:publish_category)
        end
      end
    end
  end
end
