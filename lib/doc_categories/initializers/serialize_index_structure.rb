# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class SerializeIndexStructure < Initializer
      def apply
        # add the index structure to the category serializer
        # Always include doc_category_index in the serialized output (returning nil when no valid
        # index exists) so that MessageBus updates via setProperties clear stale values on the
        # Ember store category object.
        plugin.add_to_serializer(:basic_category, :doc_category_index) do
          DocCategories::IndexSerializer
            .new(object.doc_categories_index, root: false)
            .as_json
            &.dig(:sections)
            .presence
            &.as_json
        end
      end
    end
  end
end
