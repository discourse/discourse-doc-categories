# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class RegisterMcpTools < Initializer
      def apply
        plugin.register_mcp_tool(
          "discourse_documentation_index_read",
          title: "Read documentation index",
          description: <<~TEXT.squish,
            Reads the documentation sidebar for a category. Large indexes are returned as an
            ordered page of sections and links. If the result includes a next_offset, pass it
            as offset to continue.
          TEXT
          implementation: DocCategories::McpTools::ReadIndex,
          input_schema: {
            type: "object",
            properties: {
              category_id: {
                type: "integer",
                minimum: 1,
              },
              offset: {
                type: "integer",
                minimum: 0,
                description: "Request an ordered page starting at this entry offset.",
              },
            },
            required: %w[category_id],
            additionalProperties: false,
          },
          output_schema: DocCategories::McpTools::ReadIndex::OUTPUT_SCHEMA,
          required_scopes: DocCategories::McpTools::ReadIndex::REQUIRED_SCOPES,
          annotations: {
            readOnlyHint: true,
            destructiveHint: false,
          },
          risk: :read,
          availability: -> { UpcomingChanges.enabled?(:doc_categories_index_editor) },
        )

        plugin.register_mcp_tool(
          "discourse_documentation_index_list_unindexed_topics",
          title: "List unindexed documentation topics",
          description: <<~TEXT.squish,
            Lists category topics that are missing from the saved documentation sidebar.
            Requires a site admin. Results are paginated starting at page 0.
          TEXT
          implementation: DocCategories::McpTools::ListUnindexedTopics,
          input_schema: {
            type: "object",
            properties: {
              category_id: {
                type: "integer",
                minimum: 1,
              },
              page: {
                type: "integer",
                minimum: 0,
                maximum: DocCategories::UnindexedTopicsList::MAX_PAGE,
                default: 0,
              },
            },
            required: %w[category_id],
            additionalProperties: false,
          },
          output_schema: DocCategories::McpTools::ListUnindexedTopics::OUTPUT_SCHEMA,
          required_scopes: DocCategories::McpTools::ListUnindexedTopics::REQUIRED_SCOPES,
          annotations: {
            readOnlyHint: true,
            destructiveHint: false,
          },
          risk: :read,
          availability: -> { UpcomingChanges.enabled?(:doc_categories_index_editor) },
        )

        plugin.register_mcp_tool(
          "discourse_documentation_index_patch",
          title: "Edit documentation index",
          description: <<~TEXT.squish,
            Applies one change to a category's documentation sidebar. Add a section with optional
            topic links, move a section with its contents, append topic links, remove a section
            with its contents, or remove a topic link from a section. Use IDs from the read index
            tool. Adding a section without placement appends it at the top level.
            If the result includes a read_offset, use the read index tool with that offset
            to fetch the updated sidebar.
          TEXT
          implementation: DocCategories::McpTools::PatchIndex,
          input_schema: {
            type: "object",
            properties: {
              category_id: {
                type: "integer",
                minimum: 1,
              },
              operation: {
                type: "string",
                enum: DocCategories::IndexPatcher::OPERATIONS.keys,
              },
              title: {
                type: "string",
                minLength: 1,
                maxLength: DocCategories::SidebarSection::MAX_TITLE_LENGTH,
              },
              section_id: {
                type: "integer",
                minimum: 1,
                description: "Section to move, remove, or edit.",
              },
              placement: {
                type: "string",
                enum: DocCategories::IndexPatcher::PLACEMENTS,
                description:
                  "Place a new or moved section before, after, or inside the relative section.",
              },
              relative_section_id: {
                type: "integer",
                minimum: 1,
                description: "Section used as the placement reference.",
              },
              topic_ids: {
                type: "array",
                items: {
                  type: "integer",
                  minimum: 1,
                },
                uniqueItems: true,
                maxItems: DocCategories::Index::MAX_LINKS_PER_SECTION,
                description: "Topic IDs to link in the supplied order.",
              },
              topic_id: {
                type: "integer",
                minimum: 1,
                description: "Topic whose link to remove from the specified section.",
              },
            },
            required: %w[category_id operation],
            dependentRequired: {
              placement: %w[relative_section_id],
              relative_section_id: %w[placement],
            },
            oneOf:
              DocCategories::IndexPatcher::OPERATIONS.map do |operation, required_fields|
                optional_fields = DocCategories::IndexPatcher::OPTIONAL_FIELDS.fetch(operation, [])
                {
                  properties: {
                    operation: {
                      const: operation,
                    },
                  },
                  required: required_fields.map(&:to_s),
                  propertyNames: {
                    enum:
                      (%i[category_id operation] + required_fields + optional_fields).map(&:to_s),
                  },
                }
              end,
            additionalProperties: false,
          },
          output_schema: DocCategories::McpTools::PatchIndex::OUTPUT_SCHEMA,
          required_scopes: DocCategories::McpTools::PatchIndex::REQUIRED_SCOPES,
          annotations: {
            readOnlyHint: false,
            destructiveHint: true,
          },
          risk: :destructive,
          availability: -> { UpcomingChanges.enabled?(:doc_categories_index_editor) },
        )
      end
    end
  end
end
