# frozen_string_literal: true

RSpec.describe "Review unindexed documentation topics" do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:indexed_topic) do
    Fabricate(:topic_with_op, category: category, title: "Getting started guide")
  end
  fab!(:missing_topic) do
    Fabricate(:topic_with_op, category: category, title: "Workspace security guide")
  end
  fab!(:subcategory) { Fabricate(:category_with_definition, parent_category: category) }
  fab!(:subcategory_topic) do
    Fabricate(:topic_with_op, category: subcategory, title: "API token recipe")
  end

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.enable_simplified_category_creation = true

    index = Fabricate(:doc_categories_index, category: category, index_topic_id: -1)
    section = index.sidebar_sections.create!(title: "Start here", position: 0)
    section.sidebar_links.create!(
      topic_id: indexed_topic.id,
      href: indexed_topic.relative_url,
      position: 0,
    )
    index
      .sidebar_sections
      .create!(title: "Reference", position: 1)
      .sidebar_links
      .create!(title: "External reference", href: "https://example.com/reference", position: 0)
    sign_in(admin)
  end

  it "reviews truly missing topics without changing the draft on cancel" do
    editor.visit_doc_index_tab(category)

    expect(page).to have_css(".doc-category-index-editor__missing-topics", text: "1 topic")
    find(".doc-category-index-editor__review-topics").click

    expect(page).to have_css(".doc-category-unindexed-topics [data-topic-id='#{missing_topic.id}']")
    expect(page).to have_no_css(
      ".doc-category-unindexed-topics [data-topic-id='#{indexed_topic.id}']",
    )
    expect(page).to have_no_css(
      ".doc-category-unindexed-topics [data-topic-id='#{category.topic_id}']",
    )
    expect(page).to have_no_css(
      ".doc-category-unindexed-topics [data-topic-id='#{subcategory_topic.id}']",
    )

    find(".doc-category-unindexed-topics .d-modal-cancel").click

    expect(page).to have_no_css(".doc-category-unindexed-topics")
    expect(page).to have_css(".doc-category-index-editor__apply-btn[disabled]")
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: indexed_topic.title,
      count: 1,
    )
  end

  it "adds reviewed topics to the draft, updates the count, and supports undo" do
    editor.visit_doc_index_tab(category)
    find(".doc-category-index-editor__review-topics").click
    PageObjects::Components::FormKit
      .new(".doc-category-unindexed-topics .form-kit")
      .field("topic_#{missing_topic.id}")
      .check
    find(".doc-category-unindexed-topics__add").click

    expect(page).to have_no_css(".doc-category-unindexed-topics")
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: missing_topic.title,
      count: 1,
    )
    expect(page).to have_no_css(".doc-category-index-editor__link.--duplicate")
    expect(page).to have_no_css(".doc-category-index-editor__missing-topics", text: "1 topic")

    find(".doc-category-index-editor__undo-add").click

    expect(page).to have_no_css(".doc-category-index-editor__link-label", text: missing_topic.title)
    expect(page).to have_css(".doc-category-index-editor__missing-topics", text: "1 topic")
  end

  it "reviews missing topics from a section without duplicating other sections" do
    editor.visit_doc_index_tab(category)
    within all(".doc-category-index-editor__section").last do
      find(".d-combo-button-menu").click
    end
    find(
      "button",
      text: I18n.t("js.doc_categories.category_settings.index_editor.add_missing_topics"),
      exact_text: true,
    ).click

    expect(page).to have_css(".doc-category-unindexed-topics [data-topic-id='#{missing_topic.id}']")
    expect(page).to have_no_css(
      ".doc-category-unindexed-topics [data-topic-id='#{indexed_topic.id}']",
    )
    expect(
      find(".doc-category-unindexed-topics select").find("option", text: "Reference"),
    ).to be_selected
    PageObjects::Components::FormKit
      .new(".doc-category-unindexed-topics .form-kit")
      .field("topic_#{missing_topic.id}")
      .check
    find(".doc-category-unindexed-topics__add").click

    within all(".doc-category-index-editor__section").last do
      expect(page).to have_css(".doc-category-index-editor__link-label", text: missing_topic.title)
    end
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: indexed_topic.title,
      count: 1,
    )
    expect(page).to have_no_css(".doc-category-index-editor__link.--duplicate")
  end

  it "keeps the advisory and review available with a long external draft link" do
    editor.visit_doc_index_tab(category)
    editor.add_manual_link(
      title: "Tracked external reference",
      url: "https://example.com/?tracking=#{"x" * 2200}",
    )

    expect(page).to have_css(".doc-category-index-editor__missing-topics", text: "1 topic")
    find(".doc-category-index-editor__review-topics").click

    expect(page).to have_css(".doc-category-unindexed-topics [data-topic-id='#{missing_topic.id}']")
    expect(page).to have_no_css(".doc-category-unindexed-topics .alert-error")
  end

  it "can create a new destination without changing existing sections" do
    editor.visit_doc_index_tab(category)
    find(".doc-category-index-editor__review-topics").click
    form = PageObjects::Components::FormKit.new(".doc-category-unindexed-topics .form-kit")
    form.field("section_id").select("new")
    form.field("topic_#{missing_topic.id}").check
    find(".doc-category-unindexed-topics__add").click

    expect(editor).to have_section_title(
      I18n.t("js.doc_categories.category_settings.index_editor.all_topics_section"),
    )
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: indexed_topic.title,
      count: 1,
    )
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: missing_topic.title,
      count: 1,
    )
    editor.click_apply
    expect(editor).to have_applied

    page.refresh

    expect(editor).to have_section_title("Start here")
    expect(editor).to have_section_title("Reference")
    expect(editor).to have_section_title(
      I18n.t("js.doc_categories.category_settings.index_editor.all_topics_section"),
    )
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: missing_topic.title,
      count: 1,
    )
  end

  it "includes subcategories on request and persists additions only after Apply" do
    editor.visit_doc_index_tab(category)
    find(".doc-category-index-editor__review-topics").click
    form = PageObjects::Components::FormKit.new(".doc-category-unindexed-topics .form-kit")
    form.field("include_subcategories").toggle

    expect(page).to have_css(
      ".doc-category-unindexed-topics [data-topic-id='#{subcategory_topic.id}']",
    )
    form.field("topic_#{subcategory_topic.id}").check
    find(".doc-category-unindexed-topics__add").click
    editor.click_apply
    expect(editor).to have_applied

    page.refresh

    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: subcategory_topic.title,
      count: 1,
    )
    expect(page).to have_css(
      ".doc-category-index-editor__link-label",
      text: indexed_topic.title,
      count: 1,
    )
  end
end
