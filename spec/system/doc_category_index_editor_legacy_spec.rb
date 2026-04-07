# frozen_string_literal: true

describe "Doc Category Index Editor (Legacy)" do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic for testing") }
  fab!(:post_1) { Fabricate(:post, topic: topic_1) }

  let(:editor) { PageObjects::Components::DocIndexEditor.new }
  let(:modal) { PageObjects::Modals::DocIndexEditor.new }
  let(:dialog) { PageObjects::Components::Dialog.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.enable_simplified_category_creation = false
    sign_in(admin)
  end

  it "renders mode dropdown in legacy category settings" do
    editor.visit_category_settings(category)
    expect(editor).to have_legacy_mode_dropdown
  end

  context "with editor mode" do
    it "shows Open editor button when switching to editor mode" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      expect(editor).to have_legacy_editor_trigger
    end

    it "opens the editor modal" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor
      expect(modal).to be_open
    end

    it "adds a section and link in the modal and applies" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor

      modal.add_section(title: "Legacy Section")
      modal.add_manual_link(title: "Legacy Link", url: "https://example.com/legacy")
      modal.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Legacy Section")
      expect(index.sidebar_sections.first.sidebar_links.count).to eq(1)
      expect(index.sidebar_sections.first.sidebar_links.first.title).to eq("Legacy Link")
    end

    it "shows flash error in modal when applying with validation errors" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor

      modal.add_empty_section
      modal.click_apply

      expect(modal).to have_flash_error
    end

    it "shows validation errors below the open editor button after closing modal" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor

      modal.add_empty_section
      modal.close
      expect(modal).to be_closed

      expect(editor).to have_editor_validation_errors
    end

    it "blocks category save with a dialog when editor has validation errors" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor

      modal.add_empty_section
      modal.close
      expect(modal).to be_closed

      editor.save_legacy_category
      expect(dialog).to have_content(
        I18n.t("js.doc_categories.category_settings.index_editor.save_validation_error"),
      )
    end

    it "applies successfully when switching from topic mode to editor mode" do
      DocCategories::Index.create!(category: category, index_topic: topic_1)

      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      expect(dialog).to have_content(
        I18n.t("js.doc_categories.category_settings.index_editor.switch_to_direct_warning"),
      )
      dialog.click_yes
      editor.click_open_editor
      expect(modal).to be_open

      modal.add_section(title: "After Topic")
      modal.add_manual_link(title: "New Link", url: "https://example.com/new")
      modal.click_apply
      expect(editor).to have_applied

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.mode_direct?).to eq(true)
      expect(index.sidebar_sections.first.title).to eq("After Topic")
    end

    it "persists editor state via transient data without needing Apply" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor

      modal.add_section(title: "Persistent Section")
      modal.add_manual_link(title: "Persistent Link", url: "https://example.com/persist")
      modal.close
      expect(modal).to be_closed

      editor.click_open_editor
      expect(modal).to be_open
      expect(modal).to have_section_title("Persistent Section")
    end
  end

  context "with index topic mode" do
    it "shows topic chooser and saves" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_topic")
      expect(editor).to have_legacy_topic_mode

      editor.select_index_topic(topic_1)
      expect(editor).to have_selected_topic(topic_1)

      editor.save_legacy_category
      expect(page).to have_css(".edit-category", wait: 5)

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.index_topic_id).to eq(topic_1.id)
    end
  end

  context "when switching to disabled mode" do
    it "clears data when switching to disabled mode" do
      editor.visit_category_settings(category)
      editor.switch_legacy_mode("mode_direct")
      editor.click_open_editor

      modal.add_section(title: "To Delete")
      modal.add_manual_link(title: "Delete Me", url: "https://example.com/delete")
      modal.click_apply
      expect(editor).to have_applied
      modal.close

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

      editor.switch_legacy_mode("mode_none")
      expect(dialog).to have_content(
        I18n.t("js.doc_categories.category_settings.index_editor.disable_confirm"),
      )
      dialog.click_yes
      editor.save_legacy_category
      expect(page).to have_css(".edit-category", wait: 5)

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end
  end
end
