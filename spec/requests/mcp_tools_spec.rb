# frozen_string_literal: true

describe "Documentation index MCP tools" do
  fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:group)
  fab!(:private_group, :group)
  fab!(:category, :category_with_definition)
  fab!(:index) { Fabricate(:doc_categories_index, category:) }
  fab!(:section) { Fabricate(:doc_categories_sidebar_section, index:, title: "Testing") }
  fab!(:subsection) do
    Fabricate(:doc_categories_sidebar_section, index:, parent_section: section, title: "QUnit")
  end
  fab!(:topic) { Fabricate(:topic, category:) }
  fab!(:link) do
    Fabricate(
      :doc_categories_sidebar_link,
      sidebar_section: subsection,
      topic:,
      href: topic.relative_url,
      title: nil,
    )
  end

  let(:read_scope) { DocCategories::McpTools::ReadIndex::REQUIRED_SCOPES.fetch(0) }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.mcp_server_enabled = true
    group.add(user)
    McpPrimitive.find_or_initialize_by(
      kind: "tool",
      identifier: "discourse_documentation_index_read",
    ).update!(enabled: true)
  end

  def authorize(*extra_scopes)
    scopes = [DiscourseMcp::INITIAL_SCOPE, *extra_scopes]
    scopes.each { |scope| McpGroupScope.create!(group:, scope:) }
    client =
      McpOauthClient.create!(
        client_id: SecureRandom.hex,
        name: "Documentation index test client",
        registration_type: "pre_registered",
        trust_state: "approved",
        redirect_uris: ["http://127.0.0.1/callback"],
      )
    authorization =
      DiscourseMcp::OAuth::AuthorizationGrant.create!(
        user:,
        client:,
        redirect_uri: client.redirect_uris.first,
        requested_scopes: scopes,
      )
    @token = McpOauthAccessToken.issue!(authorization:)
  end

  def call_read_index
    call_mcp_tool("discourse_documentation_index_read", category_id: category.id)
  end

  def call_mcp_tool(name, **arguments)
    post "/mcp",
         params: {
           jsonrpc: "2.0",
           id: 1,
           method: "tools/call",
           params: {
             name:,
             arguments:,
           },
         }.to_json,
         headers: {
           "HTTP_AUTHORIZATION" => "Bearer #{@token}",
           "CONTENT_TYPE" => "application/json",
           "HTTP_ACCEPT" => "application/json, text/event-stream",
           "HTTP_MCP_PROTOCOL_VERSION" => DiscourseMcp::LEGACY_PROTOCOL_VERSION,
         }
  end

  describe "read index" do
    context "when the user can view the category" do
      before do
        category.set_permissions(group => :readonly)
        category.save!
      end

      it "requires the documentation index read scope" do
        authorize

        call_read_index

        expect(response.status).to eq(403), response.body
        expect(response.headers["WWW-Authenticate"]).to include(
          'error="insufficient_scope"',
          "scope=\"#{read_scope}\"",
        )
      end

      it "returns the nested index when the token has the read scope" do
        authorize(read_scope)

        call_read_index

        expect(response.status).to eq(200), response.body
        result = response.parsed_body.fetch("result")
        expect(result["isError"]).to eq(false)
        expect(result["structuredContent"]).to eq(
          "sections" => [
            {
              "id" => section.id,
              "text" => section.title,
              "items" => [
                {
                  "id" => subsection.id,
                  "text" => subsection.title,
                  "type" => "section",
                  "links" => [
                    {
                      "text" => topic.title,
                      "href" => link.href,
                      "topic_id" => topic.id,
                      "topic_title" => topic.title,
                      "custom_title" => false,
                    },
                  ],
                },
              ],
            },
          ],
        )
      end
    end

    context "when the user cannot view the category" do
      before do
        category.set_permissions(private_group => :readonly)
        category.save!
      end

      it "returns a tool error without the index" do
        authorize(read_scope)

        call_read_index

        expect(response.status).to eq(200), response.body
        result = response.parsed_body.fetch("result")
        expect(result["isError"]).to eq(true)
        expect(result["content"]).to eq(
          [{ "type" => "text", "text" => I18n.t("mcp_tools.errors.category_not_found") }],
        )
        expect(result).not_to have_key("structuredContent")
      end
    end
  end

  describe "patch index" do
    fab!(:user) { Fabricate(:admin, refresh_auto_groups: true) }
    fab!(:other_section) { Fabricate(:doc_categories_sidebar_section, index:, title: "Themes") }
    fab!(:first_topic) { Fabricate(:topic, category:) }
    fab!(:second_topic) { Fabricate(:topic, category:) }

    let(:write_scope) { "discourse-doc-categories:write_index" }

    before do
      index.update!(index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT)
      McpPrimitive.find_or_initialize_by(
        kind: "tool",
        identifier: "discourse_documentation_index_patch",
      ).update!(enabled: true)
    end

    def call_patch_index(category_id: category.id, **arguments)
      call_mcp_tool("discourse_documentation_index_patch", category_id:, **arguments)
    end

    def tool_result
      expect(response.status).to eq(200), response.body
      response.parsed_body.fetch("result")
    end

    def patched_sections
      result = tool_result
      expect(result["isError"]).to eq(false), response.body
      result.fetch("structuredContent").fetch("sections")
    end

    def expect_patch_error(translation_key)
      expect(tool_result).to include(
        "isError" => true,
        "content" => [{ "type" => "text", "text" => I18n.t(translation_key) }],
      )
    end

    it "requires the write scope even when the token has the read scope" do
      authorize(read_scope)

      call_patch_index(operation: "add_section", title: "UI")

      expect(response.status).to eq(403), response.body
      expect(response.headers["WWW-Authenticate"]).to include(
        'error="insufficient_scope"',
        "scope=\"#{write_scope}\"",
      )
    end

    context "when the token belongs to a non-admin" do
      fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }

      it "returns a tool error without changing the index" do
        authorize(write_scope)

        expect { call_patch_index(operation: "add_section", title: "UI") }.not_to change {
          index.sidebar_sections.count
        }
        expect_patch_error("doc_categories.errors.index_admin_required")
      end
    end

    it "creates an index with a section and the requested topics in order" do
      new_category = Fabricate(:category_with_definition)
      authorize(write_scope)

      call_patch_index(
        category_id: new_category.id,
        operation: "add_section",
        title: "UI",
        topic_ids: [second_topic.id, first_topic.id],
      )

      returned_sections = patched_sections
      created_section = new_category.reload.doc_categories_index.sidebar_sections.sole
      expect(returned_sections).to eq(
        [
          {
            "id" => created_section.id,
            "text" => "UI",
            "links" =>
              [second_topic, first_topic].map do |linked_topic|
                {
                  "text" => linked_topic.title,
                  "href" => linked_topic.relative_url,
                  "topic_id" => linked_topic.id,
                  "topic_title" => linked_topic.title,
                  "custom_title" => false,
                }
              end,
          },
        ],
      )
      expect(created_section.sidebar_links.pluck(:topic_id)).to eq(
        [second_topic.id, first_topic.id],
      )
    end

    it "adds sections immediately before and after an existing section" do
      authorize(write_scope)

      call_patch_index(
        operation: "add_section",
        title: "Before testing",
        placement: "before",
        relative_section_id: section.id,
      )
      expect(patched_sections.pluck("text")).to eq(
        ["Before testing", section.title, other_section.title],
      )

      call_patch_index(
        operation: "add_section",
        title: "After testing",
        placement: "after",
        relative_section_id: section.id,
      )

      expect(patched_sections.pluck("text")).to eq(
        ["Before testing", section.title, "After testing", other_section.title],
      )
      expect(index.sidebar_sections.pluck(:title)).to include("After testing")
    end

    it "makes an empty nested section discoverable so its topic links can be added later" do
      authorize(read_scope, write_scope)

      call_patch_index(
        operation: "add_section",
        title: "Integration tests",
        placement: "inside",
        relative_section_id: section.id,
      )
      nested_section = patched_sections.first.fetch("items").last

      call_read_index
      expect(patched_sections.first.fetch("items")).to match(
        [hash_including("id" => subsection.id), nested_section],
      )
      expect(nested_section).to include("text" => "Integration tests", "links" => [])

      call_patch_index(
        operation: "add_topic_links",
        section_id: nested_section.fetch("id"),
        topic_ids: [first_topic.id],
      )

      expect(patched_sections.first.fetch("items").last.fetch("links").pluck("topic_id")).to eq(
        [first_topic.id],
      )
    end

    it "inserts a nested section among sibling sections and links without changing their order" do
      sibling_link =
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: section,
          topic:,
          href: topic.relative_url,
          position: subsection.position + 1,
        )
      authorize(write_scope)

      call_patch_index(
        operation: "add_section",
        title: "Before QUnit",
        placement: "before",
        relative_section_id: subsection.id,
      )

      expect(patched_sections.first.fetch("items").pluck("text")).to eq(
        ["Before QUnit", subsection.title, sibling_link.title],
      )
      expect(section.sidebar_links.pluck(:id)).to eq([sibling_link.id])
    end

    it "moves an existing section above and below another section while keeping its contents" do
      authorize(write_scope)

      call_patch_index(
        operation: "move_section",
        section_id: section.id,
        placement: "after",
        relative_section_id: other_section.id,
      )
      expect(patched_sections.pluck("id")).to eq([other_section.id, section.id])

      call_patch_index(
        operation: "move_section",
        section_id: section.id,
        placement: "before",
        relative_section_id: other_section.id,
      )

      expect(patched_sections.pluck("id")).to eq([section.id, other_section.id])
      expect(subsection.reload.parent_section_id).to eq(section.id)
      expect(link.reload.sidebar_section_id).to eq(subsection.id)
    end

    it "moves a section inside a different parent" do
      authorize(write_scope)

      call_patch_index(
        operation: "move_section",
        section_id: subsection.id,
        placement: "inside",
        relative_section_id: other_section.id,
      )

      expect(patched_sections.find { |entry| entry.fetch("id") == other_section.id }).to include(
        "items" => [hash_including("id" => subsection.id, "type" => "section")],
      )
      expect(subsection.reload.parent_section_id).to eq(other_section.id)
    end

    it "appends new topic links in order and keeps the existing link to a requested topic" do
      authorize(write_scope)

      call_patch_index(
        operation: "add_topic_links",
        section_id: subsection.id,
        topic_ids: [second_topic.id, topic.id, first_topic.id],
      )

      topic_ids = [topic.id, second_topic.id, first_topic.id]
      returned_subsection = patched_sections.first.fetch("items").first
      expect(returned_subsection.fetch("links").pluck("topic_id")).to eq(topic_ids)
      expect(subsection.sidebar_links.pluck(:topic_id)).to eq(topic_ids)
      expect(link.reload.sidebar_section_id).to eq(subsection.id)
    end

    it "removes only the topic link in the named section" do
      other_link =
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: other_section,
          topic:,
          href: topic.relative_url,
        )
      authorize(write_scope)

      call_patch_index(
        operation: "remove_topic_link",
        section_id: subsection.id,
        topic_id: topic.id,
      )

      expect(patched_sections.first.fetch("items").first.fetch("links")).to eq([])
      expect(subsection.sidebar_links).to be_empty
      expect(other_section.sidebar_links.pluck(:id)).to eq([other_link.id])
    end

    it "removes a section with its subsections and links" do
      authorize(write_scope)
      removed_link_id = link.id

      call_patch_index(operation: "remove_section", section_id: section.id)

      expect(patched_sections.pluck("id")).to eq([other_section.id])
      expect(index.sidebar_sections.pluck(:id)).to eq([other_section.id])
      expect(DocCategories::SidebarLink.exists?(removed_link_id)).to eq(false)
    end

    it "rejects a section removal request that also specifies a topic ID" do
      authorize(write_scope)

      expect do
        call_patch_index(operation: "remove_section", section_id: section.id, topic_id: topic.id)
      end.not_to change { index.sidebar_sections.pluck(:id) }

      expect(response.parsed_body.fetch("error")).to include("code" => -32_602)
    end

    it "rejects moving a section inside its own descendant" do
      authorize(write_scope)

      expect do
        call_patch_index(
          operation: "move_section",
          section_id: section.id,
          placement: "inside",
          relative_section_id: subsection.id,
        )
      end.not_to change { index.sidebar_sections.pluck(:id, :parent_section_id, :position) }
      expect_patch_error("doc_categories.errors.invalid_section_move")
    end

    it "rejects section IDs from a different category's index" do
      unrelated_section = Fabricate(:doc_categories_sidebar_section)
      authorize(write_scope)

      expect do
        call_patch_index(
          operation: "add_section",
          title: "UI",
          placement: "inside",
          relative_section_id: unrelated_section.id,
        )
      end.not_to change(DocCategories::SidebarSection, :count)
      expect_patch_error("doc_categories.errors.index_section_not_found")
    end

    it "rejects the entire patch when a topic comes from another private category" do
      private_topic =
        Fabricate(:topic, category: Fabricate(:private_category, group: private_group))
      authorize(write_scope)

      expect do
        call_patch_index(
          operation: "add_topic_links",
          section_id: subsection.id,
          topic_ids: [first_topic.id, private_topic.id],
        )
      end.not_to change { subsection.sidebar_links.pluck(:topic_id) }
      expect_patch_error("doc_categories.errors.index_topic_unavailable")
    end

    it "leaves a topic-managed index intact" do
      index.update!(index_topic: topic)
      authorize(write_scope)

      expect {
        call_patch_index(operation: "remove_section", section_id: section.id)
      }.not_to change { index.sidebar_sections.pluck(:id) }
      expect_patch_error("doc_categories.errors.index_topic_managed")
      expect(index.reload).to be_mode_topic
    end
  end
end
