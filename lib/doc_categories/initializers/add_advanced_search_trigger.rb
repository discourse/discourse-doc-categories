# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class AddAdvancedSearchTrigger < Initializer
      def apply
        ::Search.advanced_filter(/in:docs/) do |posts|
          next posts unless SiteSetting.doc_categories_enabled

          target_category_ids =
            Category
              .doc_category_ids
              .flat_map { |category_id| Category.subcategory_ids(category_id) }
              .uniq

          posts.where("category_id IN (?)", target_category_ids)
        end
      end
    end
  end
end
