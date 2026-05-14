# frozen_string_literal: true

describe "Doc Category Auto-Index" do
  fab!(:admin)
  fab!(:category)
  fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic for auto-indexing") }
  fab!(:post_1) { Fabricate(:post, topic: topic_1) }
  fab!(:topic_2) { Fabricate(:topic, category: category, title: "Beta topic for auto-indexing") }
  fab!(:post_2) { Fabricate(:post, topic: topic_2) }

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
  end

  context "when adding an auto-index section" do
    it "creates an auto-index section with a placeholder and saves it" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_auto_index_section

      expect(editor).to have_auto_index_section
      expect(editor).to have_auto_index_placeholder
      expect(editor).to have_no_auto_index_button

      editor.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)

      section = index.sidebar_sections.first
      expect(section.auto_index).to eq(true)
      expect(section.title).to eq(
        I18n.t("js.doc_categories.category_settings.index_editor.auto_index_section_title"),
      )
    end

    it "backfills existing topics after applying" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      editor.add_auto_index_section
      editor.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      auto_links = index.auto_index_section.sidebar_links.auto_indexed
      expect(auto_links.pluck(:topic_id)).to contain_exactly(topic_1.id, topic_2.id)
    end

    it "coexists with manual sections" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      editor.add_section(title: "Manual Section").add_manual_link(
        title: "Manual Link",
        url: "https://example.com",
      )
      editor.add_auto_index_section

      editor.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.sidebar_sections.count).to eq(2)
      expect(index.sidebar_sections.find_by(auto_index: false).title).to eq("Manual Section")
      expect(index.sidebar_sections.find_by(auto_index: true)).to be_present
    end
  end

  context "with the auto-index badge dropdown" do
    it "toggles include subcategories via the badge dropdown" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      editor.add_auto_index_section

      expect(editor).to have_auto_index_badge_with_text(
        I18n.t("js.doc_categories.category_settings.index_editor.auto_index_badge_label"),
      )

      editor.toggle_include_subcategories
      # Confirm in the dialog
      find(".dialog-footer .btn-primary").click

      expect(editor).to have_auto_index_badge_with_text(
        I18n.t(
          "js.doc_categories.category_settings.index_editor.auto_index_badge_label_with_subcategories",
        ),
      )
    end

    it "shows resync pending state in the badge" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      editor.add_auto_index_section

      editor.click_resync_button

      expect(editor).to have_auto_index_badge_with_text(
        I18n.t("js.doc_categories.category_settings.index_editor.resync_auto_index"),
      )
    end

    it "includes subcategory topics after enabling and applying" do
      subcategory = Fabricate(:category, parent_category: category)
      Fabricate(:topic, category: subcategory, title: "Subcategory topic for auto-index")

      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      editor.add_auto_index_section
      editor.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      sub_topic_ids = Topic.where(category_id: subcategory.id).pluck(:id)
      auto_topic_ids = index.auto_index_section.sidebar_links.auto_indexed.pluck(:topic_id)
      expect(auto_topic_ids & sub_topic_ids).to be_empty

      editor.toggle_include_subcategories
      find(".dialog-footer .btn-primary").click

      editor.click_apply
      expect(editor).to have_applied

      index.reload
      auto_topic_ids = index.auto_index_section.sidebar_links.auto_indexed.pluck(:topic_id)
      expect(auto_topic_ids & sub_topic_ids).not_to be_empty
    end
  end

  context "with auto-index event hooks" do
    before do
      index =
        DocCategories::Index.create!(
          category: category,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      DocCategories::SidebarSection.create!(
        index: index,
        title: "Topics",
        position: 0,
        auto_index: true,
      )
    end

    it "adds a new topic to the auto-index section" do
      new_topic = Fabricate(:topic, category: category, title: "New auto-indexed topic for testing")
      Fabricate(:post, topic: new_topic)

      DocCategories::AutoIndexer::AddTopic.call(params: { topic_id: new_topic.id })

      index = DocCategories::Index.find_by(category_id: category.id)
      auto_links = index.auto_index_section.sidebar_links.auto_indexed
      expect(auto_links.find_by(topic_id: new_topic.id)).to be_present
    end

    it "removes a trashed topic from the auto-index section" do
      index = DocCategories::Index.find_by(category_id: category.id)

      DocCategories::AutoIndexer::AddTopic.call(params: { topic_id: topic_1.id })
      expect(index.auto_index_section.sidebar_links.auto_indexed.count).to eq(1)

      DocCategories::AutoIndexer::RemoveTopic.call(params: { topic_id: topic_1.id })
      expect(index.auto_index_section.sidebar_links.auto_indexed.count).to eq(0)
    end
  end
end
