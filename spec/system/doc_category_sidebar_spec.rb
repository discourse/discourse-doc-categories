# frozen_string_literal: true

describe "Doc Category Sidebar", system: true do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:topic) { Fabricate(:topic_with_op, category: category) }
  fab!(:documentation_category, :category_with_definition)
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
        * [#{documentation_topic3.title}](/t/#{documentation_topic3.slug})
        * #{documentation_topic4.slug}: [#{documentation_topic4.title}](/t/#{documentation_topic4.slug}/#{documentation_topic4.id})
        * No link

        ## Empty section

      MD
    end
  end

  let(:sidebar) { PageObjects::Components::NavigationMenu::Sidebar.new }
  let(:filter) { PageObjects::Components::Filter.new }

  let(:default_sidebar_sections) do
    [
      {
        title: "General Usage",
        links: [
          doc_link_for(documentation_topic),
          doc_link_for(documentation_topic2, title: documentation_topic2.slug),
        ],
      },
      {
        title: "Writing",
        links: [
          doc_link_for(documentation_topic3),
          doc_link_for(documentation_topic3, slug_only: true),
          doc_link_for(documentation_topic4, title: documentation_topic4.slug),
        ],
      },
    ]
  end

  let!(:documentation_index) do
    create_doc_categories_index(
      category: documentation_category,
      index_topic: index_topic,
      sections: default_sidebar_sections,
    )
  end

  def docs_section_name(title)
    "discourse-docs-sidebar__#{Slug.for(title)}"
  end

  def doc_link_for(topic, title: nil, slug_only: false)
    href = slug_only ? "/t/#{topic.slug}" : topic.relative_url
    { title: title || topic.title, href: href, topic: topic }
  end

  def create_doc_categories_index(category:, index_topic:, sections: [])
    DocCategories::Index
      .create!(category: category, index_topic: index_topic)
      .tap do |index|
        sections.each_with_index do |section_data, section_position|
          section =
            index.sidebar_sections.create!(title: section_data[:title], position: section_position)

          section_data[:links].each_with_index do |link_data, link_position|
            section.sidebar_links.create!(
              title: link_data[:title],
              href: link_data[:href],
              topic: link_data[:topic],
              position: link_position,
            )
          end
        end
      end
  end

  before do
    SiteSetting.navigation_menu = "sidebar"
    SiteSetting.doc_categories_enabled = true
    Site.clear_cache
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

    expect(sidebar).to have_section_link(
      documentation_topic3.title,
      href: %r{t/#{documentation_topic3.slug}$},
    )

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

      create_doc_categories_index(
        category: documentation_subcategory,
        index_topic: subcategory_index_topic,
        sections: [
          {
            title: "Subcategory Index",
            links: [
              doc_link_for(documentation_topic),
              doc_link_for(documentation_topic2, title: documentation_topic2.slug),
            ],
          },
        ],
      )
      Site.clear_cache

      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

      expect(sidebar).to be_visible
      expect_docs_sidebar_to_be_correct

      visit("/c/#{documentation_subcategory.slug}/#{documentation_subcategory.id}")

      expect(sidebar).to be_visible
      expect(sidebar).to have_section(docs_section_name("Subcategory Index"))
    end
  end

  context "when in category settings" do
    before do
      Jobs.run_immediately!
      sign_in(admin)
    end

    it "correctly saves the new index topic" do
      new_doc_topic = Fabricate(:topic_with_op, category: documentation_category)
      another_doc_topic = Fabricate(:topic_with_op, category: documentation_category)
      new_index_topic =
        Fabricate(:topic, category: documentation_category).tap do |t|
          Fabricate(:post, topic: t, raw: <<~MD)
            ## Getting Started

            * [#{new_doc_topic.title}](/t/#{new_doc_topic.slug}/#{new_doc_topic.id})

            ## Additional Resources

            * #{another_doc_topic.slug}: [#{another_doc_topic.title}](/t/#{another_doc_topic.slug}/#{another_doc_topic.id})
          MD
        end

      SearchIndexer.enable
      SearchIndexer.index(new_index_topic, force: true)

      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")
      expect_docs_sidebar_to_be_correct

      category_page = PageObjects::Pages::Category.new
      category_page.visit_settings(documentation_category)

      topic_chooser =
        PageObjects::Components::SelectKit.new(
          ".doc-categories-settings__index-topic .topic-chooser",
        )
      topic_chooser.expand
      topic_chooser.search(new_index_topic.id)
      topic_chooser.select_row_by_index(0)

      category_page.save_settings
      expect(category_page.find("#save-category")).to have_content(I18n.t("js.category.save"))
      expect(topic_chooser).to have_selected_name(new_index_topic.title)

      page.refresh
      scroll_to(find(".doc-categories-settings__index-topic .topic-chooser"))

      wait_for(timeout: Capybara.default_max_wait_time * 2) do
        expect(topic_chooser).to have_selected_name(new_index_topic.title)
      end
      expect(topic_chooser.value).to eq(new_index_topic.id.to_s)

      visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

      expect(sidebar).to be_visible
      expect(sidebar).to have_section(docs_section_name("Getting Started"))
      expect(sidebar).to have_section_link(
        new_doc_topic.title,
        href: %r{t/#{new_doc_topic.slug}/#{new_doc_topic.id}},
      )
      expect(sidebar).to have_section(docs_section_name("Additional Resources"))
      expect(sidebar).to have_section_link(
        another_doc_topic.slug,
        href: %r{t/#{another_doc_topic.slug}/#{another_doc_topic.id}},
      )
      expect(sidebar).to have_no_section(docs_section_name("General Usage"))
      expect(sidebar).to have_no_section(docs_section_name("Writing"))
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
      expect(page).to have_css(
        ".sidebar-section-link.active[data-link-name*='#{documentation_topic.title.parameterize}']",
      )

      visit("/t/#{documentation_topic3.slug}/#{documentation_topic3.id}")
      expect(page).to have_css(
        ".sidebar-section-link.active[data-link-name*='#{documentation_topic3.title.parameterize}']",
      )
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
        "We couldn’t find anything matching ‘missing’.\nDo you want to perform a search on this category or a site wide search instead?",
      )

      suggested_category_search = page.find(".docs-sidebar-suggested-category-search")
      expect(suggested_category_search[:href]).to end_with(
        "/search?q=missing%20%23#{documentation_category.slug}",
      )

      site_wide_search = page.find(".docs-sidebar-suggested-site-search")
      expect(site_wide_search[:href]).to end_with("/search?q=missing")

      # for subcategories
      create_doc_categories_index(
        category: documentation_subcategory,
        index_topic: Fabricate(:topic, category: documentation_subcategory),
        sections: [{ title: "Subcategory Docs", links: [doc_link_for(documentation_topic)] }],
      )
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
      create_doc_categories_index(
        category: documentation_subsubcategory,
        index_topic: Fabricate(:topic, category: documentation_subsubcategory),
        sections: [{ title: "Third Level Docs", links: [doc_link_for(documentation_topic)] }],
      )
      filter.filter("missing")

      suggested_category_search = page.find(".docs-sidebar-suggested-category-search")
      expect(suggested_category_search[:href]).to end_with(
        "/search?q=missing%20category%3A#{documentation_subsubcategory.id}",
      )
    end
  end

  it "links correctly back to forum" do
    sign_in(admin)

    visit("/c/#{documentation_category.slug}/#{documentation_category.id}")
    page.first(".sidebar-section-link-content-text").click
    visit(
      "/c/#{documentation_category.slug}/#{documentation_subcategory.slug}/#{documentation_subcategory.id}",
    )
    sidebar.click_back_to_forum

    expect(page).to have_current_path("/")
  end
end
