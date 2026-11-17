# frozen_string_literal: true

RSpec.describe "Documentation category type" do
  fab!(:admin)
  fab!(:category, :category_with_definition)

  let(:banner) { PageObjects::Components::AdminChangesBanner.new }
  let(:category_page) { PageObjects::Pages::Category.new }
  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
  end

  it "opens the visual editor in the native tab after creating a Documentation category" do
    SiteSetting.doc_categories_enabled = false
    category_page.visit_new_category
    card = PageObjects::Components::CategoryTypeCard.new.find_type_card("documentation")
    expect(card).to have_css(".category-type-cards__card-icon .d-icon-book")
    card.click
    PageObjects::Components::FormKit.new(".form-kit").field("name").fill_in("Product docs")
    editor.switch_to_doc_index_tab
    expect(page).to have_no_content(I18n.t("js.category.type_settings_schema.site_settings"))
    banner.click_save

    expect(page).to have_css(".edit-category-documentation", count: 1)
    editor.switch_to_doc_index_tab

    expect(editor).to have_editor
    expect(page).to have_button("Add section", disabled: false)
    expect(page).to have_no_css(".edit-category-doc-index")
    expect(SiteSetting.doc_categories_enabled).to eq(true)
    expect(Category.find_by!(name: "Product docs").doc_categories_index).to be_mode_direct
  end

  it "previews the editor with disabled controls before the category is created" do
    category_page.visit_new_category
    PageObjects::Components::CategoryTypeCard.new.find_type_card("documentation").click
    editor.switch_to_doc_index_tab

    expect(page).to have_content(
      I18n.t("js.doc_categories.category_settings.sidebar_structure_editor.create_category_first"),
    )
    expect(page).to have_css(".doc-category-index-tab__mode-trigger[disabled]", text: "Editor")
    expect(page).to have_button("Add section", disabled: true)
    expect(page).to have_no_css(".doc-category-index-tab button:not([disabled])")
  end

  it "asks moderators to have an admin enable the plugin" do
    SiteSetting.doc_categories_enabled = false
    SiteSetting.moderators_manage_categories = true
    sign_in(Fabricate(:moderator))

    category_page.visit_new_category
    card = PageObjects::Components::CategoryTypeCard.new.find_type_card("documentation")

    expect(card).to have_button("Documentation", disabled: true)
    expect(card).to have_content("Requires Documentation Categories plugin")
    expect(card).to have_button("Ask an admin to enable the Documentation Categories plugin")
  end

  it "preserves the topic index when the Documentation type is added and removed" do
    topic = Fabricate(:topic, category:)
    index = Fabricate(:doc_categories_index, category:, index_topic: topic)
    category_page.visit_general(category)
    selector = PageObjects::Components::DMenu.new(".category-type-selector")
    selector.expand
    selector.option(".category-type-selector__result.--category-type-documentation").click
    banner.click_save

    expect(page).to have_css(".edit-category-documentation")
    editor.switch_to_doc_index_tab
    expect(editor).to have_topic_mode

    category_page.visit_general(category)
    selector.remove_selected_option(I18n.t("category_types.documentation.name"))
    banner.click_save

    expect(banner).to be_hidden
    expect(page).to have_no_css(".edit-category-documentation")
    expect(index.reload.index_topic_id).to eq(topic.id)
  end
end
