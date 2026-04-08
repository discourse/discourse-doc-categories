# frozen_string_literal: true

describe "Doc Category Index Editor" do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic for testing") }
  fab!(:post_1) { Fabricate(:post, topic: topic_1) }

  let(:editor) { PageObjects::Components::DocIndexEditor.new }
  let(:dialog) { PageObjects::Components::Dialog.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
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

    it "saves doc-index sections via the Apply button" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section(title: "Applied Section").add_manual_link(
        title: "Applied Link",
        url: "https://example.com/applied",
      )

      editor.click_apply
      expect(editor).to have_applied
      expect(editor).to have_no_pending_changes

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Applied Section")
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

    it "preserves doc-index state across tab switches" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section(title: "Persistent Section").add_manual_link(
        title: "Persistent Link",
        url: "https://example.com/persistent",
      )

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

    it "saves a first section with empty title via Apply" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      editor.add_section_without_title
      editor.add_manual_link(title: "My Link", url: "https://example.com")

      editor.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("")
      expect(index.sidebar_sections.first.sidebar_links.first.title).to eq("My Link")
    end

    it "disables Apply when there are validation errors" do
      editor.visit_doc_index_tab(category).switch_to_mode("mode_direct")
      expect(editor).to have_editor

      # A section without links triggers "must contain at least one item"
      editor.add_section(title: "Empty Section")
      expect(editor).to have_apply_disabled

      editor.add_manual_link(title: "Link", url: "https://example.com")
      expect(editor).to have_no_apply_disabled
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

      editor.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present

      editor.switch_to_mode("mode_none")
      expect(dialog).to have_content(
        I18n.t("js.doc_categories.category_settings.index_editor.disable_confirm"),
      )
      dialog.click_yes
      expect(editor).to have_none_help

      editor.save_category
      expect(editor).to have_no_pending_changes

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end
  end
end
