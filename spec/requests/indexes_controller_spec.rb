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

    it "returns all topics in the category with total_count" do
      sign_in(admin)

      get "/doc-categories/indexes/#{category.id}/topics.json"

      expect(response.status).to eq(200)

      body = response.parsed_body
      topics = body["topics"]
      expect(topics.map { |t| t["id"] }).to contain_exactly(topic_1.id, topic_2.id, topic_3.id)
      expect(body["total_count"]).to eq(3)

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

    it "rejects updates when the index is in topic mode" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category)
      Fabricate(:doc_categories_index, category: category, index_topic: topic)

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [{ title: "Section 1", links: [{ title: "Link 1", href: "/t/test/1" }] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(403)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.mode_topic?).to eq(true)
      expect(index.sidebar_sections.count).to eq(0)
    end

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

      category_response = response.parsed_body["category"]
      expect(category_response["doc_category_index"]).to be_nil
    end

    it "switches from topic mode to direct mode when force_direct is true" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category)
      Fabricate(:doc_categories_index, category: category, index_topic: topic)

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            force_direct: true,
            sections: [{ title: "Section 1", links: [{ title: "Link 1", href: "/t/test/1" }] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.mode_direct?).to eq(true)
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Section 1")
    end

    it "allows updates when the index is in direct mode" do
      sign_in(admin)
      DocCategories::Index.create!(
        category: category,
        index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
      )

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [{ title: "Updated", links: [{ title: "Link", href: "/t/test/1" }] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.sidebar_sections.first.title).to eq("Updated")
    end

    it "includes empty auto-index sections in the response structure" do
      sign_in(admin)

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [
              { title: "Manual", links: [{ title: "Link", href: "/t/test/1" }] },
              { title: "Topics", auto_index: true, links: [] },
            ],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)

      structure = response.parsed_body["index_structure"]
      expect(structure.length).to eq(2)
      expect(structure[1]["text"]).to eq("Topics")
      expect(structure[1]["auto_index"]).to eq(true)
    end

    it "runs auto-indexer sync when creating auto-index section via category save" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category, title: "Auto-indexed topic for sync testing")
      Fabricate(:post, topic: topic)

      sections = [{ title: "Topics", auto_index: true, links: [] }].to_json

      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: sections,
          }

      expect(response.status).to eq(200)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.auto_index_section).to be_present
      expect(index.auto_index_section.sidebar_links.count).to be > 0
    end

    it "re-syncs auto-index section when it is removed and re-added without an id" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category, title: "Topic that should be auto-indexed")
      Fabricate(:post, topic: topic)

      # First save: creates auto-index section, sync runs and populates links
      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: [{ title: "Topics", auto_index: true, links: [] }] }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index = DocCategories::Index.find_by(category_id: category.id)
      old_section = index.auto_index_section
      expect(old_section.sidebar_links.count).to be > 0

      # Second save: user removed and re-added a new auto-index section (no id sent)
      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: [{ title: "New Topics", auto_index: true, links: [] }] }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index.reload
      expect(index.auto_index_section).to be_present
      expect(index.auto_index_section.sidebar_links.count).to be > 0
    end

    it "does not re-sync when the same auto-index section is saved with its id" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category, title: "Topic that should be auto-indexed")
      Fabricate(:post, topic: topic)

      # First save: creates auto-index section, sync runs
      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: [{ title: "Topics", auto_index: true, links: [] }] }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index = DocCategories::Index.find_by(category_id: category.id)
      old_section = index.auto_index_section
      auto_links = old_section.sidebar_links.auto_indexed.to_a

      # User removes the one auto-indexed topic from the section
      # and re-saves with the same section id (preserving identity)
      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            sections: [{ id: old_section.id, title: "Topics", auto_index: true, links: [] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index.reload
      expect(index.auto_index_section).to be_present
      # Sync did not run, so no links were re-added
      expect(index.auto_index_section.sidebar_links.auto_indexed.count).to eq(0)
    end

    it "re-syncs when force_sync is true even if section id is preserved" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category, title: "Topic for force sync")
      Fabricate(:post, topic: topic)

      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: [{ title: "Topics", auto_index: true, links: [] }] }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index = DocCategories::Index.find_by(category_id: category.id)
      section = index.auto_index_section
      expect(section.sidebar_links.auto_indexed.count).to be > 0

      # Remove auto-indexed links manually, then re-save with same section id
      section.sidebar_links.auto_indexed.destroy_all
      expect(section.sidebar_links.auto_indexed.count).to eq(0)

      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            force_sync: true,
            sections: [{ id: section.id, title: "Topics", auto_index: true, links: [] }],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index.reload
      expect(index.auto_index_section.sidebar_links.auto_indexed.count).to be > 0
    end

    it "re-syncs when auto_index_include_subcategories changes" do
      sign_in(admin)
      subcategory = Fabricate(:category, parent_category: category)
      topic = Fabricate(:topic, category: subcategory, title: "Subcategory topic")
      Fabricate(:post, topic: topic)

      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: [{ title: "Topics", auto_index: true, links: [] }] }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index = DocCategories::Index.find_by(category_id: category.id)
      section = index.auto_index_section
      # Subcategory topic not included by default
      expect(section.sidebar_links.auto_indexed.pluck(:topic_id)).not_to include(topic.id)

      # Enable subcategories — should trigger sync and add the subcategory topic
      put "/doc-categories/indexes/#{category.id}.json",
          params: {
            auto_index_include_subcategories: true,
            sections: [
              {
                id: section.id,
                title: "Topics",
                auto_index: true,
                links:
                  section.sidebar_links.map { |l| { title: l.title, href: l.href, icon: l.icon } },
              },
            ],
          }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(200)
      index.reload
      expect(index.auto_index_include_subcategories).to eq(true)
      expect(index.auto_index_section.sidebar_links.auto_indexed.pluck(:topic_id)).to include(
        topic.id,
      )
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

    it "returns 400 when sections exceed the limit" do
      sign_in(admin)

      sections =
        (DocCategories::IndexSaver::MAX_SECTIONS + 1).times.map do |i|
          { title: "Section #{i}", links: [{ title: "Link", href: "/t/s/#{i}" }] }
        end

      put "/doc-categories/indexes/#{category.id}.json",
          params: { sections: sections }.to_json,
          headers: {
            "CONTENT_TYPE" => "application/json",
          }

      expect(response.status).to eq(400)
      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end

    it "creates an index with sections via category save using doc_index_sections" do
      sign_in(admin)

      sections = [{ title: "Via Category", links: [{ title: "Link", href: "/t/test/1" }] }].to_json

      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: sections,
          }

      expect(response.status).to eq(200)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.mode_direct?).to eq(true)
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Via Category")
      expect(index.sidebar_sections.first.sidebar_links.first.title).to eq("Link")
    end

    it "saves auto-index section via category save with doc_index_sections" do
      sign_in(admin)

      sections = [{ title: "Topics", auto_index: true, links: [] }].to_json

      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: sections,
          }

      expect(response.status).to eq(200)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.auto_index).to eq(true)
      expect(index.sidebar_sections.first.title).to eq("Topics")
    end

    it "returns 400 when doc_index_sections contains invalid JSON" do
      sign_in(admin)

      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: "not valid json {{{",
          }

      expect(response.status).to eq(400)
    end

    it "returns 400 when doc_index_sections is valid JSON but not an array" do
      sign_in(admin)

      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: '{"title":"not an array"}',
          }

      expect(response.status).to eq(400)
    end

    it "rejects doc_index_sections via category save when the index is in topic mode" do
      sign_in(admin)
      topic = Fabricate(:topic, category: category)
      Fabricate(:doc_categories_index, category: category, index_topic: topic)

      sections = [{ title: "New", links: [{ title: "Link", href: "/t/test/1" }] }].to_json

      put "/categories/#{category.id}.json",
          params: {
            name: category.name,
            color: category.color,
            text_color: category.text_color,
            doc_index_sections: sections,
          }

      expect(response.status).to eq(403)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.mode_topic?).to eq(true)
      expect(index.sidebar_sections.count).to eq(0)
    end
  end
end
