# frozen_string_literal: true

describe "Doc Category Index Editor" do
  fab!(:admin)
  fab!(:category, :documentation_category)
  fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic for testing") }
  fab!(:post_1) { Fabricate(:post, topic: topic_1) }

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
  end

  context "with the advanced settings toggle" do
    let(:category_page) { PageObjects::Pages::Category.new }

    it "shows the Documentation tab without advanced settings when the source is disabled" do
      category_page.visit_general(category)

      expect(page).to have_css(".edit-category-documentation")
      expect(page).to have_no_css(".edit-category-security")
    end

    it "hides the Documentation tab for a category with an existing index and no Documentation type" do
      discussion = Fabricate(:category_with_definition)
      Fabricate(:doc_categories_index, category: discussion, index_topic_id: -1)

      category_page.visit_settings(discussion)

      expect(page).to have_no_css(".edit-category-documentation")
    end

    it "keeps the selected tab visible after disabling its index" do
      index = Fabricate(:doc_categories_index, category: category, index_topic_id: -1)
      section = Fabricate(:doc_categories_sidebar_section, index: index)
      Fabricate(
        :doc_categories_sidebar_link,
        sidebar_section: section,
        href: "https://example.com/docs",
      )
      category_page.visit_general(category)
      find(".edit-category-documentation a").click
      expect(page).to have_css(".edit-category-security")
      category_page.toggle_advanced_settings
      expect(page).to have_no_css(".edit-category-security")

      editor.switch_to_mode("mode_none")
      editor.save_category
      expect(editor).to have_no_pending_changes

      expect(page).to have_css(".edit-category-documentation.active")
      expect(page).to have_css(".edit-category-general")
      expect(editor).to have_none_help
    end

    %i[direct topic].each do |index_mode|
      it "shows a #{index_mode == :topic ? "topic-based" : "visual"} doc index without advanced settings" do
        DocCategories::Index.create!(
          category: category,
          index_topic_id:
            index_mode == :topic ? topic_1.id : DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
        category_page.visit_general(category)

        expect(page).to have_no_css(".edit-category-security")
        find(".edit-category-documentation a").click

        expect(page).to have_css(".doc-category-index-tab")
        expect(page).to have_css(".edit-category-security")
        expect(page).to have_css(".edit-category-documentation", count: 1)

        category_page.toggle_advanced_settings

        expect(page).to have_current_path("/c/#{category.slug}/edit/documentation")
        expect(page).to have_css(".doc-category-index-tab")
        expect(page).to have_no_css(".edit-category-security")

        page.refresh

        expect(page).to have_css(".doc-category-index-tab")
        expect(page).to have_css(".edit-category-security")
      end
    end
  end

  context "when the index editor setting is disabled" do
    before { SiteSetting.doc_categories_index_editor = false }

    it "hides the doc index tab even with an existing index and advanced settings enabled" do
      Fabricate(:doc_categories_index, category: category, index_topic_id: -1)
      category_page = PageObjects::Pages::Category.new
      category_page.visit_general(category)

      expect(page).to have_no_css(".edit-category-documentation")

      category_page.toggle_advanced_settings

      expect(page).to have_css(".edit-category-security")
      expect(page).to have_no_css(".edit-category-documentation")
    end

    it "keeps the editor hidden on a direct visit to the Documentation tab" do
      DocCategories::Index.create!(
        category: category,
        index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
      )

      visit "/c/#{category.slug}/edit/documentation"
      expect(editor).to have_no_editor
    end
  end

  context "with editor mode" do
    it "saves doc-index sections atomically with the category via Save Category" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section(title: "My Section").add_manual_link(
        title: "My Link",
        url: "https://example.com",
      )

      editor.save_category
      expect(editor).to have_no_pending_changes

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("My Section")
      expect(index.sidebar_sections.first.sidebar_links.count).to eq(1)
      expect(index.sidebar_sections.first.sidebar_links.first.title).to eq("My Link")
    end

    it "saves auto-index section via Save Category" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_auto_index_section
      expect(editor).to have_auto_index_section

      editor.save_category
      expect(editor).to have_no_pending_changes

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.first.auto_index).to eq(true)
    end

    it "preserves saved doc-index state across tab switches" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section(title: "Persistent Section").add_manual_link(
        title: "Persistent Link",
        url: "https://example.com/persistent",
      )
      editor.save_category
      expect(editor).to have_no_pending_changes

      editor.switch_to_general_tab
      expect(editor).to have_no_editor

      editor.switch_to_doc_index_tab
      expect(editor).to have_editor
      expect(editor).to have_section_title("Persistent Section")
    end
  end

  context "with first section empty title" do
    it "does not auto-enter edit mode for the first section" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section_without_title

      expect(editor).to have_no_section_title_editing
      expect(editor).to have_first_section_placeholder
    end

    it "does not delete the first section when canceling title edit" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section_without_title
      expect(editor.section_count).to eq(1)

      within all(".doc-category-index-editor__section").first do
        find(".doc-category-index-editor__edit-btn").click
      end
      expect(editor).to have_section_title_editing

      editor.click_cancel_title_edit

      expect(editor).to have_no_section_title_editing
      expect(editor.section_count).to eq(1)
      expect(editor).to have_first_section_placeholder
    end

    it "saves a first section with empty title via Save Category" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section_without_title
      editor.add_manual_link(title: "My Link", url: "https://example.com")

      editor.save_category
      expect(editor).to have_no_pending_changes

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("")
      expect(index.sidebar_sections.first.sidebar_links.first.title).to eq("My Link")
    end

    it "blocks saving an empty section until a link is added" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      # A section without links triggers "must contain at least one item"
      editor.add_section(title: "Empty Section")
      editor.save_category
      expect(page).to have_content(
        I18n.t(
          "js.doc_categories.category_settings.sidebar_structure_editor.validation_empty_section",
        ),
      )
      expect(category.reload.doc_categories_index).to be_nil

      editor.add_manual_link(title: "Link", url: "https://example.com")
      editor.save_category
      expect(editor).to have_no_pending_changes
      expect(category.reload.doc_categories_index.sidebar_sections.first.title).to eq(
        "Empty Section",
      )
    end
  end

  context "with index topic mode" do
    def switch_to_topic_mode_and_select_topic
      editor.visit_doc_index_tab(category).switch_to_mode("mode_topic")
      expect(editor).to have_topic_mode
      editor.select_index_topic(topic_1)
    end

    it "displays the selected topic in the TopicChooser after picking one" do
      switch_to_topic_mode_and_select_topic
      expect(editor).to have_selected_topic(topic_1)
      expect(editor).to have_save_banner
    end

    it "saves the category with the selected index topic" do
      switch_to_topic_mode_and_select_topic
      expect(editor).to have_selected_topic(topic_1)

      editor.save_category
      expect(editor).to have_no_pending_changes

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.index_topic_id).to eq(topic_1.id)
    end
  end

  context "when switching to disabled mode" do
    it "clears doc-index when switching to disabled mode and saving" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section(title: "To Be Deleted").add_manual_link(
        title: "Delete Me",
        url: "https://example.com/delete",
      )

      editor.save_category
      expect(editor).to have_no_pending_changes

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present

      editor.switch_to_mode("mode_none")
      expect(editor).to have_none_help
      expect(index.reload).to be_mode_direct

      editor.save_category
      expect(editor).to have_no_pending_changes

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end
  end
end
