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

  def call_read_index(**arguments)
    call_mcp_tool("discourse_documentation_index_read", category_id: category.id, **arguments)
  end

  def populate_large_sidebar
    SiteSetting.mcp_max_response_bytes = 16_384
    first_position = subsection.sidebar_links.maximum(:position) + 1
    Array.new(12) do |offset|
      Fabricate(
        :doc_categories_sidebar_link,
        sidebar_section: subsection,
        href: "https://docs.example.com/guide/#{offset}?tracking=#{"x" * 1_500}",
        position: first_position + offset,
      )
    end
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
    it "returns bounded pages containing each nested entry in sidebar order" do
      external_links = populate_large_sidebar
      authorize(read_scope)

      entries = []
      offset = nil
      (external_links.size + 3).times do
        call_read_index(**(offset.nil? ? {} : { offset: }))
        expect(response.status).to eq(200), response.body
        expect(response.body.bytesize).to be <= SiteSetting.mcp_max_response_bytes
        result = response.parsed_body.fetch("result")
        expect(result["isError"]).to eq(false)
        page = result.fetch("structuredContent")
        entries.concat(page.fetch("entries"))
        offset = page.fetch("next_offset")
        break if offset.nil?
        expect(offset).to eq(entries.size)
      end

      expect(offset).to be_nil
      expect(entries.first(2)).to eq(
        [
          {
            "type" => "section",
            "id" => section.id,
            "parent_section_id" => nil,
            "text" => section.title,
          },
          {
            "type" => "section",
            "id" => subsection.id,
            "parent_section_id" => section.id,
            "text" => subsection.title,
          },
        ],
      )
      expect(entries.drop(2).pluck("type", "section_id", "href")).to eq(
        [link, *external_links].map { |entry| ["link", subsection.id, entry.href] },
      )
    end

    it "omits shared drafts and private topic URLs even without a stored topic ID" do
      private_category = Fabricate(:private_category, group: private_group)
      private_topic = Fabricate(:topic, category: private_category)
      draft_topic = Fabricate(:topic, category:)
      Fabricate(:shared_draft, topic: draft_topic, category:)
      private_links =
        [private_topic, draft_topic].map do |hidden_topic|
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: subsection,
            title: hidden_topic.title,
            href: "#{hidden_topic.relative_url}.json",
          )
        end
      authorize(read_scope)

      call_read_index

      expect(response.status).to eq(200), response.body
      result = response.parsed_body.fetch("result")
      nested_section = result.dig("structuredContent", "sections", 0, "items", 0)
      expect(nested_section.fetch("links").pluck("href")).to eq([link.href])
      expect(response.body).not_to include(
        *private_links.flat_map { |entry| [entry.title, entry.href] },
      )
    end

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

  describe "list unindexed topics" do
    fab!(:user) { Fabricate(:admin, refresh_auto_groups: true) }

    before do
      McpPrimitive.find_or_initialize_by(
        kind: "tool",
        identifier: "discourse_documentation_index_list_unindexed_topics",
      ).update!(enabled: true)
    end

    def call_list_unindexed_topics(category_id: category.id, **arguments)
      call_mcp_tool(
        "discourse_documentation_index_list_unindexed_topics",
        category_id:,
        **arguments,
      )
    end

    it "requires the documentation index read scope" do
      authorize

      call_list_unindexed_topics

      expect(response.status).to eq(403), response.body
      expect(response.headers["WWW-Authenticate"]).to include(
        'error="insufficient_scope"',
        "scope=\"#{read_scope}\"",
      )
    end

    it "lists category topics without links in the saved index" do
      href_only_topic = Fabricate(:topic, category:)
      unindexed_topic = Fabricate(:topic, category:)
      Fabricate(
        :doc_categories_sidebar_link,
        sidebar_section: subsection,
        topic: nil,
        href: href_only_topic.relative_url,
      )
      authorize(read_scope)

      call_list_unindexed_topics

      expect(response.status).to eq(200), response.body
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).to eq(false)
      expect(result.fetch("structuredContent")).to match(
        "topics" =>
          contain_exactly(
            {
              "id" => unindexed_topic.id,
              "title" => unindexed_topic.title,
              "slug" => unindexed_topic.slug,
              "category_id" => category.id,
            },
            hash_including("id" => index.index_topic_id, "category_id" => category.id),
          ),
        "total_count" => 2,
        "page" => 0,
        "per_page" => DocCategories::UnindexedTopicsList::PAGE_SIZE,
      )
    end

    it "returns an empty page with the total count when the page is beyond the results" do
      authorize(read_scope)

      call_list_unindexed_topics(page: 1)

      expect(response.status).to eq(200), response.body
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).to eq(false)
      expect(result.fetch("structuredContent")).to eq(
        "topics" => [],
        "total_count" => 1,
        "page" => 1,
        "per_page" => DocCategories::UnindexedTopicsList::PAGE_SIZE,
      )
    end

    it "lists eligible topics when the category has no saved index" do
      category_without_index = Fabricate(:category_with_definition)
      eligible_topic = Fabricate(:topic, category: category_without_index)
      authorize(read_scope)

      call_list_unindexed_topics(category_id: category_without_index.id)

      expect(response.status).to eq(200), response.body
      result = response.parsed_body.fetch("result")
      expect(result["isError"]).to eq(false)
      expect(result.fetch("structuredContent")).to include(
        "topics" => [hash_including("id" => eligible_topic.id)],
        "total_count" => 1,
      )
    end

    it "lists eligible topics from a stale sidebar while omitting shared drafts" do
      Fabricate(:shared_draft, topic: index.index_topic, category:)
      authorize(read_scope)

      call_list_unindexed_topics

      expect(response.status).to eq(200), response.body
      result = response.parsed_body.fetch("result")
      content = result.fetch("structuredContent")
      expect(content.fetch("topics").pluck("id")).to eq([topic.id])
      expect(content.fetch("total_count")).to eq(1)
    end

    it "returns a tool error for a missing category" do
      authorize(read_scope)

      call_list_unindexed_topics(category_id: Category.maximum(:id) + 1)

      expect(response.status).to eq(200), response.body
      result = response.parsed_body.fetch("result")
      expect(result).to include(
        "isError" => true,
        "content" => [
          { "type" => "text", "text" => I18n.t("mcp_tools.errors.category_not_found") },
        ],
      )
      expect(result).not_to have_key("structuredContent")
    end

    context "when the token belongs to a non-admin" do
      fab!(:user) { Fabricate(:user, refresh_auto_groups: true) }

      it "returns a tool error without exposing the topic list" do
        authorize(read_scope)

        call_list_unindexed_topics

        expect(response.status).to eq(200), response.body
        result = response.parsed_body.fetch("result")
        expect(result).to include(
          "isError" => true,
          "content" => [
            { "type" => "text", "text" => I18n.t("mcp_tools.errors.category_not_found") },
          ],
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

    it "acknowledges a committed patch when the resulting sidebar exceeds the response limit" do
      populate_large_sidebar
      authorize(read_scope, write_scope)

      call_patch_index(operation: "add_section", title: "Added after commit")

      expect(tool_result.fetch("structuredContent")).to eq(
        "applied" => true,
        "category_id" => category.id,
        "read_offset" => 0,
      )
      expect(tool_result["isError"]).to eq(false)
      expect(response.body.bytesize).to be <= SiteSetting.mcp_max_response_bytes
      expect(index.sidebar_sections.pluck(:title)).to include("Added after commit")
    end

    it "rejects a write to a category hidden from the admin" do
      category.set_permissions(private_group => :readonly)
      category.save!
      SiteSetting.suppress_secured_categories_from_admin = true
      authorize(write_scope)

      expect do call_patch_index(operation: "add_section", title: "Hidden") end.not_to change {
        index.sidebar_sections.count
      }
      expect_patch_error("mcp_tools.errors.category_not_found")
    end

    it "rejects a shared draft even in a category the admin can edit" do
      Fabricate(:shared_draft, topic: first_topic, category:)
      authorize(write_scope)

      expect do
        call_patch_index(
          operation: "add_topic_links",
          section_id: subsection.id,
          topic_ids: [second_topic.id, first_topic.id],
        )
      end.not_to change { subsection.sidebar_links.pluck(:id) }
      expect_patch_error("doc_categories.errors.index_topic_unavailable")
    end

    it "rejects making an untitled first section into a subsection" do
      section.update!(title: "")
      authorize(write_scope)

      expect do
        call_patch_index(
          operation: "move_section",
          section_id: section.id,
          placement: "inside",
          relative_section_id: other_section.id,
        )
      end.not_to change { section.reload.parent_section_id }
      expect_patch_error("doc_categories.errors.index_section_title_required")
    end

    it "rejects inserting a section before an untitled first section" do
      subsection.update!(parent_section: other_section)
      section.update!(title: "")
      authorize(write_scope)

      expect do
        call_patch_index(
          operation: "add_section",
          title: "Setup",
          placement: "before",
          relative_section_id: section.id,
        )
      end.not_to change { index.sidebar_sections.pluck(:id, :position) }
      expect_patch_error("doc_categories.errors.index_section_title_required")
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
