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
    post "/mcp",
         params: {
           jsonrpc: "2.0",
           id: 1,
           method: "tools/call",
           params: {
             name: "discourse_documentation_index_read",
             arguments: {
               category_id: category.id,
             },
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
end
