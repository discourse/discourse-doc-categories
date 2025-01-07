# frozen_string_literal: true

RSpec.describe "Doc Category Sidebar", system: true do
  fab!(:admin)
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:topic) { Fabricate(:topic_with_op, category: category) }
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:documentation_subcategory) do
    Fabricate(:category_with_definition, parent_category_id: documentation_category.id)
  end
  fab!(:documentation_topic) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:documentation_topic2) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:documentation_topic3) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:documentation_topic4) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:permalink) { Fabricate(:permalink, category_id: documentation_category.id) }
  fab!(:index_topic) do
    Fabricate(:topic, category: documentation_category).tap do |t|
      Fabricate(:post, topic: t, raw: <<~MD)
        Lorem ipsum dolor sit amet

        ## General Usage

        * No link
        * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
        * #{documentation_topic2.slug}: [#{documentation_topic2.title}](/t/#{documentation_topic2.slug}/#{documentation_topic2.id})

        ## Writing

        * [#{documentation_topic3.title}](/t/#{documentation_topic3.slug}/#{documentation_topic3.id})
        * #{documentation_topic4.slug}: [#{documentation_topic4.title}](/t/#{documentation_topic4.slug}/#{documentation_topic4.id})
        * No link

        ## Empty section

      MD
    end
  end

  let(:sidebar) { PageObjects::Components::NavigationMenu::Sidebar.new }
  let(:filter) { PageObjects::Components::Filter.new }

  def docs_section_name(title)
    "discourse-docs-sidebar__#{Slug.for(title)}"
  end

  def docs_link_name(title, section_title)
    "#{docs_section_name(section_title)}___#{Slug.for(title)}"
  end

  before do
    SiteSetting.navigation_menu = "sidebar"
    SiteSetting.doc_categories_enabled = true
    Site.clear_cache

    documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
    documentation_category.save!
  end

  context "when browsing regular pages" do
    it "displays the main sidebar" do
      visit("/categories")
      expect(sidebar).to have_section("categories")

      visit("/t/#{topic.slug}/#{topic.id}")
      expect(sidebar).to have_section("categories")
    end
  end

  def expect_docs_sidebar_to_be_correct
    expect(sidebar).to have_section(docs_section_name("General Usage"))
    expect(sidebar).to have_section(docs_section_name("Writing"))
    expect(sidebar).to have_no_section(docs_section_name("Empty section"))
    expect(sidebar).to have_no_section("categories")

    [documentation_topic, documentation_topic3].each do |topic|
      expect(sidebar).to have_section_link(topic.title, href: %r{t/#{topic.slug}/#{topic.id}})
    end

    [documentation_topic2, documentation_topic4].each do |topic|
      expect(sidebar).to have_section_link(topic.slug, href: %r{t/#{topic.slug}/#{topic.id}})
    end

    expect(sidebar).to have_no_section_link("No link")
  end

  context "when browsing a documentation category" do
    it "displays the docs sidebar correctly" do
      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

      expect(sidebar).to be_visible
      expect_docs_sidebar_to_be_correct
    end

    it "inherits the docs sidebar from the parent category if available" do
      visit("/c/#{documentation_subcategory.slug}/#{documentation_subcategory.id}")

      expect(sidebar).to be_visible
      expect_docs_sidebar_to_be_correct
    end

    it "displays correctly the subcategory index when different from the parent category" do
      subcategory_index_topic = Fabricate(:topic, category: documentation_subcategory)

      Fabricate(:post, topic: subcategory_index_topic, raw: <<~MD)
        # Subcategory Index
        * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
        * #{documentation_topic2.slug}: [#{documentation_topic2.title}](/t/#{documentation_topic2.slug}/#{documentation_topic2.id})
      MD

      documentation_subcategory.custom_fields[
        DocCategories::CATEGORY_INDEX_TOPIC
      ] = subcategory_index_topic.id
      documentation_subcategory.save!

      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

      expect(sidebar).to be_visible
      expect_docs_sidebar_to_be_correct

      visit("/c/#{documentation_subcategory.slug}/#{documentation_subcategory.id}")

      expect(sidebar).to be_visible
      expect(sidebar).to have_section(docs_section_name("Subcategory Index"))
    end
  end

  context "when using admin sidebar" do
    before { sign_in(admin) }

    it "never displays the docs sidebar" do
      visit("/admin/config/permalinks/#{permalink.id}")
      expect(sidebar).to be_visible
      expect(sidebar).to have_no_section(docs_section_name("General Usage"))
      expect(page).to have_css(".admin-panel")
    end
  end

  context "when browsing a documentation topic" do
    it "displays the docs sidebar correctly" do
      visit("/t/#{documentation_topic.slug}/#{documentation_topic.id}")

      expect(sidebar).to be_visible
      expect_docs_sidebar_to_be_correct
    end
  end

  context "when interacting with chat" do
    let(:chat_page) { PageObjects::Pages::Chat.new }

    before do
      chat_system_bootstrap
      sign_in(admin)
    end

    it "keeps the docs sidebar open instead of switching to the main panel when toggling the drawer" do
      membership =
        Fabricate(
          :user_chat_channel_membership,
          user: admin,
          chat_channel: Fabricate(:chat_channel),
        )
      admin.upsert_custom_fields(::Chat::LAST_CHAT_CHANNEL_ID => membership.chat_channel.id)
      chat_page.prefers_full_page

      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

      expect(sidebar).to be_visible
      expect_docs_sidebar_to_be_correct

      chat_page.open_from_header
      expect(sidebar).to be_visible
      expect(sidebar).to have_no_section(docs_section_name("General Usage"))

      chat_page.minimize_full_page
      expect(chat_page).to have_drawer
      expect_docs_sidebar_to_be_correct
    end
  end

  context "when filtering" do
    it "suggests filtering the content when there are no results" do
      SiteSetting.max_category_nesting = 3
      documentation_subsubcategory =
        Fabricate(:category_with_definition, parent_category_id: documentation_subcategory.id)

      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

      filter.filter("missing")
      expect(page).to have_no_css(".sidebar-section-link-content-text")
      expect(page).to have_css(".sidebar-no-results")

      no_results_description = page.find(".sidebar-no-results__description")
      expect(no_results_description.text).to eq(
        "We couldn’t find anything matching ‘missing’.\n\nDo you want to perform a search on this category or a site wide search instead?",
      )

      suggested_category_search = page.find(".docs-sidebar-suggested-category-search")
      expect(suggested_category_search[:href]).to end_with(
        "/search?q=missing%20%23#{documentation_category.slug}",
      )

      site_wide_search = page.find(".docs-sidebar-suggested-site-search")
      expect(site_wide_search[:href]).to end_with("/search?q=missing")

      # for subcategories
      visit(
        "/c/#{documentation_category.slug}/#{documentation_subcategory.slug}/#{documentation_subcategory.id}",
      )
      filter.filter("missing")

      suggested_category_search = page.find(".docs-sidebar-suggested-category-search")
      expect(suggested_category_search[:href]).to end_with(
        "/search?q=missing%20%23#{documentation_category.slug}%3A#{documentation_subcategory.slug}",
      )

      # for 3 levels deep
      visit("/c/#{documentation_subsubcategory.id}")
      filter.filter("missing")

      suggested_category_search = page.find(".docs-sidebar-suggested-category-search")
      expect(suggested_category_search[:href]).to end_with(
        "/search?q=missing%20category%3A#{documentation_subsubcategory.id}",
      )
    end
  end
end
