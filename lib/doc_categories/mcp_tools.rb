# frozen_string_literal: true

module DocCategories
  module McpTools
    class ReadIndex
      REQUIRED_SCOPES = %w[discourse-doc-categories:read_index].freeze

      LINK_PROPERTIES = {
        text: DiscourseMcp::OutputSchema::STRING,
        href: DiscourseMcp::OutputSchema::STRING,
        topic_id: DiscourseMcp::OutputSchema::INTEGER,
        topic_title: DiscourseMcp::OutputSchema::STRING_OR_NULL,
        custom_title: DiscourseMcp::OutputSchema::BOOLEAN,
      }.freeze
      LINK_OPTIONAL_FIELDS = %w[topic_id topic_title custom_title].freeze
      LINK_SCHEMA =
        DiscourseMcp::OutputSchema.object(optional: LINK_OPTIONAL_FIELDS, **LINK_PROPERTIES)
      LINK_ITEM_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          optional: LINK_OPTIONAL_FIELDS,
          **LINK_PROPERTIES,
          type: {
            const: "link",
          },
        )

      SECTION_REF = { "$ref" => "#/$defs/section" }.freeze
      SECTION_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          optional: %w[links items type],
          id: DiscourseMcp::OutputSchema::INTEGER,
          text: DiscourseMcp::OutputSchema::STRING,
          type: {
            const: "section",
          },
          links: DiscourseMcp::OutputSchema::ARRAY.merge(items: LINK_SCHEMA),
          items:
            DiscourseMcp::OutputSchema::ARRAY.merge(
              items: {
                oneOf: [LINK_ITEM_SCHEMA, SECTION_REF.merge(required: %w[type])],
              },
            ),
        ).merge(oneOf: [{ required: %w[links] }, { required: %w[items] }])

      SECTION_OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          sections:
            DiscourseMcp::OutputSchema::ARRAY.merge(
              items: SECTION_REF.merge(not: { required: %w[type] }),
            ),
        ).merge("$defs" => { section: SECTION_SCHEMA })

      def self.call(arguments:, request_context:)
        category = ::Category.find_by(id: arguments.fetch("category_id"))

        if !request_context.guardian.can_see_category?(category)
          raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.category_not_found")
        end

        DiscourseMcp::ToolHelpers.text_and_structured(
          sections: DocCategories::Initializers::SerializeIndexStructure.serialize_index(category),
        )
      end
    end

    # class CreateIndexSection
    #   REQUIRED_SCOPES = %w[documentation:write_index].freeze
    #   OUTPUT_SCHEMA =
    #     DiscourseMcp::OutputSchema.object(
    #       id: DiscourseMcp::OutputSchema::INTEGER,
    #       channel_id: DiscourseMcp::OutputSchema::INTEGER,
    #       created_at: DiscourseMcp::OutputSchema::STRING,
    #     )

    #   def self.call(arguments:, request_context:)
    #   end
    # end
  end
end
