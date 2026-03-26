# frozen_string_literal: true

describe "Doc Category Index Editor" do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:topic_1) { Fabricate(:topic, category: category, title: "Alpha topic for testing") }
  fab!(:topic_2) { Fabricate(:topic, category: category, title: "Beta topic for testing") }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
  end

  def visit_doc_index_tab
    page.visit("/c/#{category.slug}/edit/doc-index")
    expect(page).to have_css(".doc-category-index-editor")
  end

  def add_section_with_manual_link(section_title:, link_title:, link_url:)
    find("button", text: "Add section").click

    within all(".doc-category-index-editor__section").last do
      find(".doc-category-index-editor__section-title").fill_in(with: section_title)
      find(".doc-category-index-editor__confirm-title-btn").click

      find(".doc-category-index-editor__add-menu").click
    end
    find("button", text: "Add link").click

    within all(".doc-category-index-editor__section").last do
      all(".doc-category-index-editor__link-title").last.fill_in(with: link_title)
      all(".doc-category-index-editor__link-url").last.fill_in(with: link_url)
      find(".doc-category-index-editor__confirm-edit-btn").click
    end
  end

  def click_apply
    find(".doc-category-index-editor__apply-btn").click
  end

  def save_category
    find(".admin-changes-banner .btn-primary").click
  end

  it "saves doc-index sections atomically with the category via Save Category" do
    visit_doc_index_tab

    add_section_with_manual_link(
      section_title: "My Section",
      link_title: "My Link",
      link_url: "https://example.com",
    )

    save_category

    expect(page).to have_css(".fk-d-toast", wait: 5)

    index = DocCategories::Index.find_by(category_id: category.id)
    expect(index).to be_present
    expect(index.sidebar_sections.count).to eq(1)
    expect(index.sidebar_sections.first.title).to eq("My Section")
    expect(index.sidebar_sections.first.sidebar_links.count).to eq(1)
    expect(index.sidebar_sections.first.sidebar_links.first.title).to eq("My Link")
  end

  it "saves doc-index sections via the Apply button" do
    visit_doc_index_tab

    add_section_with_manual_link(
      section_title: "Applied Section",
      link_title: "Applied Link",
      link_url: "https://example.com/applied",
    )

    click_apply

    expect(page).to have_button(
      I18n.t("js.doc_categories.category_settings.index_editor.applied"),
      disabled: true,
      wait: 5,
    )

    index = DocCategories::Index.find_by(category_id: category.id)
    expect(index).to be_present
    expect(index.sidebar_sections.count).to eq(1)
    expect(index.sidebar_sections.first.title).to eq("Applied Section")
  end

  it "preserves doc-index state across tab switches" do
    visit_doc_index_tab

    add_section_with_manual_link(
      section_title: "Persistent Section",
      link_title: "Persistent Link",
      link_url: "https://example.com/persistent",
    )

    find("li.edit-category-general a").click
    expect(page).to have_no_css(".doc-category-index-editor")

    find("li.edit-category-doc-index a").click
    expect(page).to have_css(".doc-category-index-editor")

    expect(page).to have_css(
      ".doc-category-index-editor__section-title-label",
      text: "Persistent Section",
    )
  end
end
