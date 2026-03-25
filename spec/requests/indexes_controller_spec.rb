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
end
