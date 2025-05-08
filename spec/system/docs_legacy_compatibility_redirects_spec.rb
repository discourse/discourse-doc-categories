# frozen_string_literal: true

RSpec.describe "Docs Category Sidebar", system: true do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:topic) { Fabricate(:topic_with_op, category: category) }
  fab!(:source_topic) do
    Fabricate(:topic, category: category).tap { |t| Fabricate(:post, topic: t, raw: <<~MD) }
        - [Link to /docs?topic=ID](/docs?topic=#{topic.id})
        - [Link to /docs](/docs)
        - [Link to /knowledge-explorer](/knowledge-explorer)
      MD
  end

  let(:category_page) { PageObjects::Pages::Category.new }
  let(:topic_page) { PageObjects::Pages::Topic.new }

  before do
    GlobalSetting.stubs(:docs_path).returns("docs")

    SiteSetting.navigation_menu = "sidebar"
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_homepage = "/c/#{category.slug}/#{category.id}"
  end

  context "when clicking a link to /docs?topic=ID" do
    it "redirects to the topic if docs legacy mode is enabled" do
      SiteSetting.doc_categories_docs_legacy_enabled = true

      topic_page.visit_topic(source_topic)
      topic_page.find("a[href='/docs?topic=#{topic.id}']").click

      expect(topic_page).to have_topic_title(topic.title)
    end

    it "404s if docs legacy mode is disabled" do
      SiteSetting.doc_categories_docs_legacy_enabled = false

      topic_page.visit_topic(source_topic)
      topic_page.find("a[href='/docs?topic=#{topic.id}']").click

      expect(page).to have_css("div.page-not-found")
    end
  end

  context "when clicking a link to /docs" do
    it "redirects to the topic if docs legacy mode is enabled" do
      SiteSetting.doc_categories_docs_legacy_enabled = true

      topic_page.visit_topic(source_topic)
      topic_page.find("a[href='/docs']").click

      expect(page).to have_current_path("/c/#{category.slug}/#{category.id}")
    end

    it "404s if docs legacy mode is disabled" do
      SiteSetting.doc_categories_docs_legacy_enabled = false

      topic_page.visit_topic(source_topic)
      topic_page.find("a[href='/docs']").click

      expect(page).to have_css("div.page-not-found")
    end

    context "when clicking a link to /knowledge-explorer" do
      it "redirects to the topic if docs legacy mode is enabled" do
        SiteSetting.doc_categories_docs_legacy_enabled = true

        topic_page.visit_topic(source_topic)
        topic_page.find("a[href='/knowledge-explorer']").click

        expect(page).to have_current_path("/c/#{category.slug}/#{category.id}")
      end

      it "404s if docs legacy mode is disabled" do
        SiteSetting.doc_categories_docs_legacy_enabled = false

        topic_page.visit_topic(source_topic)
        topic_page.find("a[href='/knowledge-explorer']").click

        expect(page).to have_css("div.page-not-found")
      end
    end
  end
end
