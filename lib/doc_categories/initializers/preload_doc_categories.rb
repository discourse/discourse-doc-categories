# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class PreloadDocCategories < Initializer
      def apply
        plugin.on(:site_all_categories_cache_query) do |categories|
          ActiveRecord::Associations::Preloader.new(
            records: categories,
            associations: {
              doc_categories_index: [:index_topic, { sidebar_sections: :sidebar_links }],
            },
          )
        end
      end
    end
  end
end
