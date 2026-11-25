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
          SerializeIndexStructure.serialize_index(object)
        end
      end

      def self.serialize_index(category, include_empty: false)
        index = category&.doc_categories_index
        return nil if index.blank?

        if index.mode_topic?
          index_topic = index.index_topic
          return nil if index_topic.blank? || index_topic.trashed?

          # Ideally we should check if the current user has access to the topic above which
          # would allow securely using topics from any category, but we can't because the
          # categories are serialized on the site serializer without a guardian in scope.
          # As a workaround we force the topic category to match the category serialized,
          # which implies the user has access.
          # NOTICE THAT SUB-CATEGORIES ARE NOT CONSIDERED BECAUSE WE CAN'T CHECK THEIR
          # PERMISSIONS
          return nil unless category.id == index_topic.category_id
        end

        index.sidebar_structure(include_empty:).presence&.as_json
      end
    end
  end
end
