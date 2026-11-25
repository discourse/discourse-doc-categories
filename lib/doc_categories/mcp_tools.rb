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

        index_result(category)
      end

      def self.index_result(category)
        sections =
          DocCategories::Initializers::SerializeIndexStructure.serialize_index(
            category,
            include_empty: true,
          )
        DiscourseMcp::ToolHelpers.text_and_structured(sections: sections || [])
      end
    end

    class ListUnindexedTopics
      REQUIRED_SCOPES = ReadIndex::REQUIRED_SCOPES
      TOPIC_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          id: DiscourseMcp::OutputSchema::INTEGER,
          title: DiscourseMcp::OutputSchema::STRING,
          slug: DiscourseMcp::OutputSchema::STRING,
          category_id: DiscourseMcp::OutputSchema::INTEGER,
        )
      OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          topics: DiscourseMcp::OutputSchema::ARRAY.merge(items: TOPIC_SCHEMA),
          total_count: DiscourseMcp::OutputSchema::INTEGER,
          page: DiscourseMcp::OutputSchema::INTEGER,
          per_page: DiscourseMcp::OutputSchema::INTEGER,
        )

      def self.call(arguments:, request_context:)
        DocCategories::UnindexedTopicsList.call(
          params: arguments,
          options: {
            exclude_saved_index: true,
          },
          guardian: request_context.guardian,
        ) do
          on_success do |topics:, total_count:, params:|
            DiscourseMcp::ToolHelpers.text_and_structured(
              topics:
                ActiveModel::ArraySerializer.new(
                  topics,
                  each_serializer: DocCategories::UnindexedTopicSerializer,
                  root: false,
                ).as_json,
              total_count:,
              page: params.page.to_i,
              per_page: DocCategories::UnindexedTopicsList::PAGE_SIZE,
            )
          end
          on_failed_contract do |contract|
            raise DiscourseMcp::ToolError, contract.errors.full_messages.join(", ")
          end
          on_model_not_found(:category) do
            raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.category_not_found")
          end
          on_failed_policy(:can_list_topics) do
            raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.category_not_found")
          end
          on_failure do
            raise DiscourseMcp::ToolError,
                  I18n.t("doc_categories.errors.unindexed_topics_unavailable")
          end
        end
      end
    end

    class PatchIndex
      REQUIRED_SCOPES = %w[discourse-doc-categories:write_index].freeze

      def self.call(arguments:, request_context:)
        DocCategories::IndexPatcher.call(params: arguments, guardian: request_context.guardian) do
          on_success { |category:| ReadIndex.index_result(category) }
          on_failed_contract do |contract|
            raise DiscourseMcp::ToolError, contract.errors.full_messages.join(", ")
          end
          on_failed_policy(:can_edit_index) do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_admin_required")
          end
          on_model_not_found(:category) do
            raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.category_not_found")
          end
          on_failed_policy(:not_topic_managed) do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_topic_managed")
          end
          on_failed_step(:apply_patch) { |step| raise DiscourseMcp::ToolError, step.error }
          on_failure do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_patch_failed")
          end
        end
      end
    end
  end
end
