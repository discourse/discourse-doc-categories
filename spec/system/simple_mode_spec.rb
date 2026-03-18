# frozen_string_literal: true

describe "Doc Categories Simple Mode", system: true do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:documentation_category, :category_with_definition)
  fab!(:documentation_topic) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:documentation_topic_2) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:reply_1) { Fabricate(:post, topic: documentation_topic, raw: "This is the first reply") }
  fab!(:reply_2) { Fabricate(:post, topic: documentation_topic, raw: "This is the second reply") }
  fab!(:reply_3) { Fabricate(:post, topic: documentation_topic, raw: "This is the third reply") }
  fab!(:reply_on_topic_2) do
    Fabricate(:post, topic: documentation_topic_2, raw: "A reply on the second doc topic")
  end
  fab!(:index_topic) do
    Fabricate(:topic, category: documentation_category).tap do |t|
      Fabricate(:post, topic: t, raw: <<~MD)
        ## Docs

        * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
        * [#{documentation_topic_2.title}](/t/#{documentation_topic_2.slug}/#{documentation_topic_2.id})
      MD
    end
  end

  let(:topic_page) { PageObjects::Pages::Topic.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_simple_mode = true

    DocCategories::Index
      .create!(category: documentation_category, index_topic: index_topic)
      .tap do |index|
        section = index.sidebar_sections.create!(title: "Docs", position: 0)
        section.sidebar_links.create!(
          title: documentation_topic.title,
          href: documentation_topic.relative_url,
          topic: documentation_topic,
          position: 0,
        )
        section.sidebar_links.create!(
          title: documentation_topic_2.title,
          href: documentation_topic_2.relative_url,
          topic: documentation_topic_2,
          position: 1,
        )
      end

    sign_in(admin)
  end

  it "hides replies and shows them on toggle" do
    topic_page.visit_topic(documentation_topic)

    expect(page).to have_css("[data-post-number='1']")
    expect(page).to have_no_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_no_css("[data-post-number='3']", visible: :visible)
    expect(page).to have_no_css("[data-post-number='4']", visible: :visible)
    expect(page).to have_no_css(".post__topic-map.--op", visible: :visible)
    expect(page).to have_no_css(".topic-map.--bottom", visible: :visible)

    expect(page).to have_css(".doc-simple-mode-toggle__button", text: /Show 3 comments/)

    find(".doc-simple-mode-toggle__button").click

    expect(page).to have_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_css("[data-post-number='3']", visible: :visible)
    expect(page).to have_css("[data-post-number='4']", visible: :visible)
    expect(page).to have_no_css(".post__topic-map.--op", visible: :visible)
    expect(page).to have_css(".topic-map.--bottom", visible: :visible)

    expect(page).to have_css(".doc-simple-mode-toggle__button", text: "Hide comments")

    find(".doc-simple-mode-toggle__button").click

    expect(page).to have_no_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_no_css("[data-post-number='3']", visible: :visible)
    expect(page).to have_no_css("[data-post-number='4']", visible: :visible)
    expect(page).to have_no_css(".post__topic-map.--op", visible: :visible)
    expect(page).to have_no_css(".topic-map.--bottom", visible: :visible)

    find(".doc-simple-mode-toggle__button").click

    expect(page).to have_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_css("[data-post-number='3']", visible: :visible)
    expect(page).to have_css("[data-post-number='4']", visible: :visible)
    expect(page).to have_no_css(".post__topic-map.--op", visible: :visible)
    expect(page).to have_css(".topic-map.--bottom", visible: :visible)

    expect(page).to have_css(".doc-simple-mode-toggle__button", text: "Hide comments")
  end

  it "does not jump to the bottom when showing comments" do
    topic_page.visit_topic(documentation_topic)

    page.execute_script(<<~JS)
      window.scrollTo(0, document.scrollingElement.scrollHeight);
    JS

    initial_scroll_y = page.evaluate_script("window.scrollY")
    initial_button_top = page.evaluate_script(<<~JS)
      document
        .querySelector(".doc-simple-mode-toggle__button")
        .getBoundingClientRect()
        .top
    JS

    find(".doc-simple-mode-toggle__button").click

    expect(page).to have_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_current_path(documentation_topic.url, ignore_query: true)

    current_scroll_y = page.evaluate_script("window.scrollY")
    current_button_top = page.evaluate_script(<<~JS)
      document
        .querySelector(".doc-simple-mode-toggle__button")
        .getBoundingClientRect()
        .top
    JS

    expect(current_scroll_y).to be_within(5).of(initial_scroll_y)
    expect(current_button_top).to be_within(5).of(initial_button_top)
  end

  it "shows comments after entering the topic on a reply url" do
    visit("#{documentation_topic.relative_url}/#{reply_3.post_number}")

    expect(page).to have_css(".doc-simple-mode-toggle__button", text: /Show 3 comments/)
    expect(page).to have_current_path(documentation_topic.url, ignore_query: true)

    page.execute_script(<<~JS)
      document
        .querySelector(".doc-simple-mode-toggle__button")
        .scrollIntoView({ block: "center" });
    JS

    find(".doc-simple-mode-toggle__button").click

    expect(page).to have_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_css("[data-post-number='3']", visible: :visible)
    expect(page).to have_css("[data-post-number='4']", visible: :visible)
  end

  it "resets comments state when navigating between doc topics" do
    topic_page.visit_topic(documentation_topic)

    find(".doc-simple-mode-toggle__button").click
    expect(page).to have_css("[data-post-number='2']", visible: :visible)

    find(
      ".sidebar-section-link[data-link-name*='#{documentation_topic_2.title.parameterize}']",
    ).click

    expect(page).to have_css("h1 .fancy-title", text: documentation_topic_2.title)
    expect(page).to have_no_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_css(".doc-simple-mode-toggle__button", text: /Show 1 comment/)
  end

  it "does not affect non-doc categories" do
    regular_topic = Fabricate(:topic_with_op, category: category)
    Fabricate(:post, topic: regular_topic, raw: "A reply in a regular topic")

    topic_page.visit_topic(regular_topic)

    expect(page).to have_css("[data-post-number='1']")
    expect(page).to have_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_no_css(".doc-simple-mode-toggle")
  end

  it "does not apply when setting is disabled" do
    SiteSetting.doc_categories_simple_mode = false

    topic_page.visit_topic(documentation_topic)

    expect(page).to have_css("[data-post-number='1']")
    expect(page).to have_css("[data-post-number='2']", visible: :visible)
    expect(page).to have_no_css(".doc-simple-mode-toggle")
  end
end
