# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class PreloadDocCategories < Initializer
      def apply
        plugin.register_modifier(:site_all_categories_cache_query) do |query|
          if SiteSetting.doc_categories_enabled
            query =
              query.includes(
                doc_categories_index: [:index_topic, { sidebar_sections: :sidebar_links }],
              )
          end

          query
        end
      end
    end
  end
end
