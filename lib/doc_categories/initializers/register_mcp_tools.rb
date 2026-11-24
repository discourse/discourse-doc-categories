# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class RegisterMcpTools < Initializer
      def apply
        plugin.register_mcp_tool(
          "discourse_documentation_index_read",
          title: "Read documentation index",
          description: "Reads the documentation sidebar structure index for a category",
          implementation: DocCategories::McpTools::ReadIndex,
          input_schema: {
            type: "object",
            properties: {
              category_id: {
                type: "integer",
                minimum: 1,
              },
            },
            required: %w[category_id],
            additionalProperties: false,
          },
          output_schema: DocCategories::McpTools::ReadIndex::SECTION_OUTPUT_SCHEMA,
          required_scopes: DocCategories::McpTools::ReadIndex::REQUIRED_SCOPES,
          annotations: {
            readOnlyHint: false,
            destructiveHint: false,
          },
          risk: :read,
          availability: -> { UpcomingChanges.enabled?(:doc_categories_index_editor) },
        )
      end
    end
  end
end
