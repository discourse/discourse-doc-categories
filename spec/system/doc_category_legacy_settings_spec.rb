# frozen_string_literal: true

describe "Doc category legacy settings" do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:index_topic) { Fabricate(:topic_with_op, category: category, title: "Documentation index") }

  let(:category_page) { PageObjects::Pages::Category.new }
  let(:settings) { PageObjects::Components::DocCategorySettings.new }
  let(:banner) { PageObjects::Components::AdminChangesBanner.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = false
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
  end

  it "lets admins select, change, reset, and clear the index topic with the editor disabled" do
    replacement_topic = Fabricate(:topic_with_op, category: category, title: "Replacement index")
    category_page.visit_settings(category)

    expect(settings).to have_index_topic_chooser
    expect(settings).to have_no_editor_tab
    expect(banner).to be_hidden

    settings.select_index_topic(index_topic)
    banner.click_save
    expect(banner).to be_hidden
    page.refresh
    expect(settings).to have_index_topic(index_topic)

    settings.select_index_topic(replacement_topic)
    banner.click_discard
    expect(banner).to be_hidden
    expect(settings).to have_index_topic(index_topic)

    settings.select_index_topic(replacement_topic)
    banner.click_save
    expect(banner).to be_hidden
    page.refresh
    expect(settings).to have_index_topic(replacement_topic)

    settings.clear_index_topic
    banner.click_save
    expect(banner).to be_hidden
    page.refresh
    expect(settings).to have_no_index_topic
  end

  it "keeps the legacy chooser hidden when the editor is enabled" do
    SiteSetting.doc_categories_index_editor = true
    category_page.visit_settings(category)

    expect(settings).to have_editor_tab
    expect(settings).to have_no_index_topic_chooser
  end

  it "keeps both configuration controls hidden when doc categories are disabled" do
    SiteSetting.doc_categories_enabled = false
    category_page.visit_settings(category)

    expect(settings).to have_no_editor_tab
    expect(settings).to have_no_index_topic_chooser
  end

  it "keeps an existing visual index when saving unrelated legacy category settings" do
    index = Fabricate(:doc_categories_index, category: category, index_topic_id: -1)
    section = Fabricate(:doc_categories_sidebar_section, index: index, title: "Existing section")
    link = Fabricate(:doc_categories_sidebar_link, sidebar_section: section)
    category_page.visit_settings(category)

    expect(settings).to have_index_topic_chooser
    expect(settings).to have_no_index_topic
    expect(banner).to be_hidden

    settings.change_featured_topic_count(5)
    banner.click_save
    expect(banner).to be_hidden
    page.refresh
    expect(settings).to have_no_index_topic

    editor = PageObjects::Components::DocIndexEditor.new
    editor.visit_doc_index_tab(category.reload)
    expect(editor).to have_editor
    expect(editor).to have_section_title(section.title)
    expect(editor).to have_link_order([link.title])
  end
end
