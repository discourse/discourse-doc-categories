# frozen_string_literal: true

module DocCategories
  module McpTools
    class IndexResult
      PAGE_SIZE = 50

      def initialize(category, request_context:)
        @request_context = request_context
        @category = category
        @sections =
          DocCategories::IndexSerializer
            .new(category.doc_categories_index, root: false, include_empty: true)
            .as_json
            &.dig(:sections) || []
      end

      def read(offset:)
        if offset.nil?
          result = full_result
          return result if @request_context.result_fits?(result)
        end

        page(offset || 0)
      end

      def patch
        result = full_result
        return result if @request_context.result_fits?(result)

        DiscourseMcp::ToolHelpers.text_and_structured(
          applied: true,
          category_id: @category.id,
          read_offset: 0,
        )
      end

      private

      def full_result
        DiscourseMcp::ToolHelpers.text_and_structured(sections: @sections)
      end

      def page(offset)
        entries = flatten_sections(@sections)
        page_entries = offset < entries.size ? entries.slice(offset, PAGE_SIZE) : []
        loop do
          next_offset = offset + page_entries.size
          value = {
            entries: page_entries,
            next_offset: next_offset < entries.size ? next_offset : nil,
          }
          result = DiscourseMcp::ToolHelpers.text_and_structured(value)
          return result if @request_context.result_fits?(result)

          if page_entries.size <= 1
            result[:content] = [{ type: "text", text: I18n.t("mcp_tools.index_page_structured") }]
            return result if @request_context.result_fits?(result)

            raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.index_entry_too_large")
          end
          page_entries = page_entries.first(page_entries.size / 2)
        end
      end

      def flatten_sections(sections, parent_section_id = nil)
        sections.flat_map do |section|
          section_id = section.fetch(:id)
          entries = section[:items] || section.fetch(:links)
          [
            { type: "section", id: section_id, parent_section_id:, text: section.fetch(:text) },
            *entries.flat_map do |entry|
              if entry[:type] == "section"
                flatten_sections([entry], section_id)
              else
                entry.merge(type: "link", section_id:)
              end
            end,
          ]
        end
      end
    end

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

      PAGE_ENTRY_SCHEMA = {
        oneOf: [
          DiscourseMcp::OutputSchema.object(
            type: {
              const: "section",
            },
            id: DiscourseMcp::OutputSchema::INTEGER,
            parent_section_id: DiscourseMcp::OutputSchema::INTEGER_OR_NULL,
            text: DiscourseMcp::OutputSchema::STRING,
          ),
          DiscourseMcp::OutputSchema.object(
            optional: LINK_OPTIONAL_FIELDS,
            **LINK_PROPERTIES,
            type: {
              const: "link",
            },
            section_id: DiscourseMcp::OutputSchema::INTEGER,
          ),
        ],
      }.freeze
      PAGE_OUTPUT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          entries: DiscourseMcp::OutputSchema::ARRAY.merge(items: PAGE_ENTRY_SCHEMA),
          next_offset: DiscourseMcp::OutputSchema::INTEGER_OR_NULL,
        )
      OUTPUT_SCHEMA = {
        :type => "object",
        "$defs" => SECTION_OUTPUT_SCHEMA.fetch("$defs"),
        :oneOf => [SECTION_OUTPUT_SCHEMA.except("$defs"), PAGE_OUTPUT_SCHEMA],
      }.freeze

      def self.call(arguments:, request_context:)
        category = ::Category.find_by(id: arguments.fetch("category_id"))

        if !request_context.guardian.can_see_category?(category)
          raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.category_not_found")
        end

        IndexResult.new(category, request_context:).read(offset: arguments["offset"]&.to_i)
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
      ACKNOWLEDGMENT_SCHEMA =
        DiscourseMcp::OutputSchema.object(
          applied: {
            const: true,
          },
          category_id: DiscourseMcp::OutputSchema::INTEGER,
          read_offset: DiscourseMcp::OutputSchema::INTEGER,
        )
      OUTPUT_SCHEMA = {
        :type => "object",
        "$defs" => ReadIndex::SECTION_OUTPUT_SCHEMA.fetch("$defs"),
        :oneOf => [ReadIndex::SECTION_OUTPUT_SCHEMA.except("$defs"), ACKNOWLEDGMENT_SCHEMA],
      }.freeze

      def self.call(arguments:, request_context:)
        DocCategories::IndexPatcher.call(params: arguments, guardian: request_context.guardian) do
          on_success { |category:| IndexResult.new(category, request_context:).patch }
          on_failed_contract do |contract|
            raise DiscourseMcp::ToolError, contract.errors.full_messages.join(", ")
          end
          on_failed_policy(:can_edit_index) do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_admin_required")
          end
          on_model_not_found(:category) do
            raise DiscourseMcp::ToolError, I18n.t("mcp_tools.errors.category_not_found")
          end
          on_failed_policy(:index_editor_enabled) do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_editor_unavailable")
          end
          on_failed_policy(:not_topic_managed) do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_topic_managed")
          end
          on_failed_step(:prepare_patch) { |step| raise DiscourseMcp::ToolError, step.error }
          on_failed_step(:apply_patch) { |step| raise DiscourseMcp::ToolError, step.error }
          on_failure do
            raise DiscourseMcp::ToolError, I18n.t("doc_categories.errors.index_patch_failed")
          end
        end
      end
    end
  end
end
