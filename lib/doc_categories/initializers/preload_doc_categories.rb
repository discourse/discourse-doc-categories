# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class PreloadDocCategories < Initializer
      def apply
        plugin.register_modifier(:site_all_categories_cache_query) do |query|
          # sometimes the association is not loaded yet
          if SiteSetting.doc_categories_enabled &&
               Category.reflect_on_association(:doc_categories_index)
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
