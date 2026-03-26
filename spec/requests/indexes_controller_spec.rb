# frozen_string_literal: true

RSpec.describe ::DocCategories::IndexesController do
  before { SiteSetting.doc_categories_enabled = true }

  describe "#topics" do
    fab!(:admin)
    fab!(:user)
    fab!(:category)
    fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic title here") }
    fab!(:topic_2) { Fabricate(:topic, category: category, title: "Beta topic title here") }
    fab!(:topic_3) { Fabricate(:topic, category: category, title: "Gamma topic title here") }

    it "returns 403 for anonymous users" do
      get "/doc-categories/indexes/#{category.id}/topics.json"

      expect(response.status).to eq(403)
    end

    it "returns 403 for non-admin users" do
      sign_in(user)

      get "/doc-categories/indexes/#{category.id}/topics.json"

      expect(response.status).to eq(403)
    end

    it "returns 404 for an invalid category" do
      sign_in(admin)

      get "/doc-categories/indexes/-1/topics.json"

      expect(response.status).to eq(404)
    end

    it "returns all topics in the category" do
      sign_in(admin)

      get "/doc-categories/indexes/#{category.id}/topics.json"

      expect(response.status).to eq(200)

      topics = response.parsed_body["topics"]
      expect(topics.map { |t| t["id"] }).to contain_exactly(topic_1.id, topic_2.id, topic_3.id)

      first_topic = topics.find { |t| t["id"] == topic_1.id }
      expect(first_topic["title"]).to eq(topic_1.title)
      expect(first_topic["slug"]).to eq(topic_1.slug)
    end

    it "orders topics by title" do
      sign_in(admin)

      get "/doc-categories/indexes/#{category.id}/topics.json"

      topics = response.parsed_body["topics"]
      expect(topics.map { |t| t["title"] }).to eq(
        ["Alpha topic title here", "Beta topic title here", "Gamma topic title here"],
      )
    end

    it "excludes unlisted topics" do
      topic_1.update!(visible: false)
      sign_in(admin)

      get "/doc-categories/indexes/#{category.id}/topics.json"

      topics = response.parsed_body["topics"]
      expect(topics.map { |t| t["id"] }).to contain_exactly(topic_2.id, topic_3.id)
    end

    context "with subcategories" do
      fab!(:subcategory) { Fabricate(:category, parent_category: category) }
      fab!(:subcategory_topic) do
        Fabricate(:topic, category: subcategory, title: "Subcategory topic title here")
      end

      it "excludes subcategory topics by default" do
        sign_in(admin)

        get "/doc-categories/indexes/#{category.id}/topics.json"

        topics = response.parsed_body["topics"]
        expect(topics.map { |t| t["id"] }).to contain_exactly(topic_1.id, topic_2.id, topic_3.id)
      end

      it "includes subcategory topics when include_subcategories is true" do
        sign_in(admin)

        get "/doc-categories/indexes/#{category.id}/topics.json",
            params: {
              include_subcategories: true,
            }

        topics = response.parsed_body["topics"]
        expect(topics.map { |t| t["id"] }).to contain_exactly(
          topic_1.id,
          topic_2.id,
          topic_3.id,
          subcategory_topic.id,
        )
      end
    end
  end

  describe "#update" do
    fab!(:admin)
    fab!(:category)

    it "creates an index with sections and links" do
      sign_in(admin)

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [{ title: "Section 1", links: [{ title: "Link 1", href: "/t/test/1" }] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Section 1")
      expect(index.sidebar_sections.first.sidebar_links.count).to eq(1)
    end

    it "clears the index when doc_index_sections is empty via category save" do
      sign_in(admin)

      # First create an index via the indexes endpoint
      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [{ title: "Section 1", links: [{ title: "Link 1", href: "/t/test/1" }] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

      # Now save the category with empty doc_index_sections (simulates disabled mode)
      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: "[]",
          }

      expect(response.status).to eq(200)
      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil

      # The response should not include doc_category_index
      category_response = response.parsed_body["category"]
      expect(category_response).not_to have_key("doc_category_index")
    end

    it "clears the index when empty sections are sent via PUT to indexes endpoint" do
      sign_in(admin)

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [{ title: "Section 1", links: [{ title: "Link 1", href: "/t/test/1" }] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: [] }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end
  end
end
