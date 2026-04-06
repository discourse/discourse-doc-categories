# frozen_string_literal: true

describe "Doc Category Index Editor" do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic for testing") }
  fab!(:post_1) { Fabricate(:post, topic: topic_1) }

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

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
      expect(editor).to have_success_toast

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

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Applied Section")
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
      expect(editor).to have_success_toast

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
      expect(editor).to have_none_help

      editor.save_category
      expect(editor).to have_success_toast

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end
  end
end
