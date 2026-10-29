# frozen_string_literal: true

RSpec.describe "Doc index unsaved navigation" do
  fab!(:admin)
  fab!(:category)
  fab!(:index) { Fabricate(:doc_categories_index, category: category, index_topic_id: -1) }
  fab!(:section) do
    Fabricate(:doc_categories_sidebar_section, index: index, title: "Original section", position: 0)
  end
  fab!(:link) do
    Fabricate(
      :doc_categories_sidebar_link,
      sidebar_section: section,
      title: "Original link",
      href: "https://example.com/docs",
      position: 0,
    )
  end

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    sign_in(admin)
  end

  def edit_title(title)
    within ".doc-category-index-editor__section" do
      find(".doc-category-index-editor__section-header .doc-category-index-editor__edit-btn").click
      find(".doc-category-index-editor__section-title").fill_in(with: title)
      find(".doc-category-index-editor__confirm-title-btn").click
    end
  end

  def switch_tab(name)
    find(".edit-category-#{name} a").click
  end

  it "leaves a pristine index without a warning or dirtying the form" do
    editor.visit_doc_index_tab(category)
    switch_tab("general")
    expect(page).to have_current_path("/c/#{category.slug}/edit/general")
    expect(page).to have_no_css(".dialog-container")
    expect(page).to have_no_content("You have unsaved changes")
    switch_tab("doc-index")
    switch_tab("general")
    expect(page).to have_no_content("You have unsaved changes")
  end

  it "supports staying, and discards only index changes when leaving" do
    visit "/c/#{category.slug}/edit/general"
    find("input[name='name']").fill_in(with: "Unrelated category edit")
    switch_tab("doc-index")
    edit_title("Unsaved index title")
    switch_tab("general")
    click_button "Stay"
    expect(page).to have_current_path("/c/#{category.slug}/edit/doc-index")
    expect(page).to have_content("Unsaved index title")
    switch_tab("general")
    click_button "Discard and leave"
    expect(page).to have_current_path("/c/#{category.slug}/edit/general")
    expect(page).to have_field("name", with: "Unrelated category edit")
    switch_tab("doc-index")
    expect(page).to have_content("Original section")
    expect(page).to have_no_content("Unsaved index title")
    editor.save_category
    expect(editor).to have_no_pending_changes
    expect(category.reload.name).to eq("Unrelated category edit")
    expect(section.reload.title).to eq("Original section")
  end

  it "warns about unfinished links and discards their validation state" do
    editor.visit_doc_index_tab(category)
    find(".doc-category-index-editor__section-actions .d-combo-button-menu").click
    click_button I18n.t("js.doc_categories.category_settings.index_editor.add_link"), exact: true
    switch_tab("general")
    click_button "Discard and leave"
    switch_tab("doc-index")
    expect(page).to have_no_css(".doc-category-index-editor__link-card.--editing")
    expect(page).to have_css(".doc-category-index-editor__link", count: 1)
    edit_title("Valid later change")
    editor.save_category
    expect(editor).to have_no_pending_changes
    expect(index.reload.sidebar_sections.first.title).to eq("Valid later change")
  end

  it "uses the last applied index as the discard baseline" do
    editor.visit_doc_index_tab(category)
    edit_title("Applied title")
    editor.click_apply
    expect(editor).to have_applied
    edit_title("Later unsaved title")
    switch_tab("general")
    click_button "Discard and leave"
    switch_tab("doc-index")
    expect(page).to have_content("Applied title")
    expect(page).to have_no_content("Later unsaved title")
  end

  it "locks editing, reset, category saving, and navigation until Apply succeeds" do
    release = Queue.new
    allow(DocCategories::IndexSaver).to receive(
      :call,
    ).and_wrap_original do |original, *args, &block|
      release.pop(timeout: 15) if block
      original.call(*args, &block)
    end

    editor.visit_doc_index_tab(category)
    edit_title("Saved under lock")
    find(".doc-category-index-editor__apply-btn").native.click
    expect(page).to have_button("Applying...", disabled: true)
    expect(page).to have_css(".doc-category-index-tab[disabled]")
    expect(page).to have_no_css(".doc-category-index-tab button:not(:disabled)")
    expect(page).to have_css(".edit-category-page[inert]")
    find(".sidebar-section-link[href='/latest']").native.click
    expect(page).to have_current_path("/c/#{category.slug}/edit/doc-index")
    expect(page).to have_no_css(".dialog-container")

    release << true
    expect(editor).to have_applied
    expect(page).to have_no_css(".edit-category-page[inert]")
    expect(page).to have_button("Add section", disabled: false)
    expect(page).to have_content("Saved under lock")
    switch_tab("general")
    expect(page).to have_current_path("/c/#{category.slug}/edit/general")
  ensure
    release << true
  end

  it "unlocks after an Apply failure and preserves the draft for retry" do
    release = Queue.new
    fail_save = true
    allow(DocCategories::IndexSaver).to receive(
      :call,
    ).and_wrap_original do |original, *args, &block|
      release.pop(timeout: 15) if block
      raise Discourse::InvalidParameters.new(:sections) if fail_save
      original.call(*args, &block)
    end

    editor.visit_doc_index_tab(category)
    edit_title("Retained after failure")
    find(".doc-category-index-editor__apply-btn").native.click
    expect(page).to have_css(".edit-category-page[inert]")
    release << true
    expect(page).to have_button("OK")
    click_button "OK"
    expect(page).to have_no_css(".edit-category-page[inert]")
    expect(page).to have_content("Retained after failure")
    expect(page).to have_button("Apply", disabled: false)
    expect(section.reload.title).to eq("Original section")

    fail_save = false
    release << true
    find(".doc-category-index-editor__apply-btn").native.click
    expect(editor).to have_applied
    expect(index.reload.sidebar_sections.first.title).to eq("Retained after failure")
  ensure
    release << true
  end
end
