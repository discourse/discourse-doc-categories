# frozen_string_literal: true

RSpec.describe "Doc index capacity" do
  fab!(:admin)
  fab!(:category)
  fab!(:index) do
    Fabricate(
      :doc_categories_index,
      category: category,
      index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
    )
  end
  fab!(:section) do
    Fabricate(:doc_categories_sidebar_section, index: index, title: "Destination", position: 0)
  end

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    sign_in(admin)
  end

  def populate(section, count)
    DocCategories::SidebarLink.insert_all!(
      Array.new(count) do |position|
        {
          sidebar_section_id: section.id,
          title: "Link #{section.id}-#{position}",
          href: "/link-#{section.id}-#{position}",
          position: position,
        }
      end,
    )
  end

  it "disables both section creation options at capacity" do
    populate(section, 1)
    (DocCategories::Index::MAX_SECTIONS - 1).times do |position|
      extra =
        Fabricate(
          :doc_categories_sidebar_section,
          index: index,
          title: "Section #{position}",
          position: position + 1,
        )
      populate(extra, 1)
    end

    editor.visit_doc_index_tab(category)
    expect(page).to have_button("Add section", disabled: true)
    expect(page).to have_content(
      I18n.t(
        "js.doc_categories.category_settings.index_editor.section_limit",
        count: DocCategories::Index::MAX_SECTIONS,
      ),
    )
    find(".doc-category-index-editor__footer .d-combo-button-menu").click
    expect(page).to have_button("Add auto-index section", disabled: true)
  end

  it "rejects moving into a full section and allows moving after making room" do
    populate(section, DocCategories::Index::MAX_LINKS_PER_SECTION)
    source = Fabricate(:doc_categories_sidebar_section, index: index, title: "Source", position: 1)
    populate(source, 2)
    source_title = source.sidebar_links.first.title

    editor.visit_doc_index_tab(category)
    within all(".doc-category-index-editor__section").first do
      expect(page).to have_button("Add topic", disabled: true)
      find(".doc-category-index-editor__section-actions .d-combo-button-menu").click
    end
    expect(page).to have_button("Add link", disabled: true)
    find(".doc-category-index-editor__section-actions .d-combo-button-menu", match: :first).click

    editor.move_link_to_section(source_title, "Destination")
    expect(page).to have_css(
      ".fk-d-toast",
      text:
        I18n.t(
          "js.doc_categories.category_settings.index_editor.link_limit",
          count: DocCategories::Index::MAX_LINKS_PER_SECTION,
        ),
    )
    expect(editor.links_in_section("Source").size).to eq(2)
    expect(editor.links_in_section("Destination").size).to eq(
      DocCategories::Index::MAX_LINKS_PER_SECTION,
    )
    expect(editor).to have_no_pending_changes

    # Moving out of a full section must remain possible.
    editor.move_link_to_section(section.sidebar_links.first.title, "Source")
    expect(editor.links_in_section("Source").size).to eq(3)
    editor.move_link_to_section(source_title, "Destination")
    expect(editor.links_in_section("Source").size).to eq(2)
    expect(editor.links_in_section("Destination")).to include(source_title)
  end

  it "blocks Apply and Save Category for an oversized loaded draft" do
    populate(section, DocCategories::Index::MAX_LINKS_PER_SECTION + 1)
    editor.visit_doc_index_tab(category)
    within ".doc-category-index-editor__section" do
      find(".doc-category-index-editor__section-header .doc-category-index-editor__edit-btn").click
      find(".doc-category-index-editor__section-title").fill_in(with: "Changed title")
      find(".doc-category-index-editor__confirm-title-btn").click
    end
    expect(page).to have_button("Apply", disabled: true)
    editor.save_category
    expect(page).to have_content(
      I18n.t(
        "js.doc_categories.category_settings.index_editor.link_limit",
        count: DocCategories::Index::MAX_LINKS_PER_SECTION,
      ),
    )
    expect(section.reload.title).to eq("Destination")
  end
end
