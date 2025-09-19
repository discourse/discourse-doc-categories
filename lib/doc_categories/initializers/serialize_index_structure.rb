# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class SerializeIndexStructure < Initializer
      def apply
        plugin.add_to_serializer(:category, :doc_index_topic_id) { object.doc_index_topic_id }

        plugin.add_to_serializer(:basic_category, :doc_index_topic_id) { object.doc_index_topic_id }

        plugin.add_to_serializer(
          :basic_category,
          :doc_category_index,
          include_condition: -> do
            index =
              DocCategories::Index.includes(sidebar_sections: :sidebar_links).find_by(
                category_id: object.id,
              )
            next false if index.blank?

            topic = index.index_topic
            next false if topic.blank?
            next false if topic.private_message?
            next false if topic.trashed?
            next false unless topic.category_id == object.id

            structure = index.sidebar_structure
            next false if structure.blank?

            @doc_category_index = structure
            true
          end,
        ) { @doc_category_index.as_json }
      end
    end
  end
end
