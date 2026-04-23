# frozen_string_literal: true

describe "Doc Categories Simple Mode" do
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
  let(:toggle) { PageObjects::Components::DocSimpleModeToggle.new }

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
    expect(page).to have_no_css("[data-post-number='2']")
    expect(page).to have_no_css("[data-post-number='3']")
    expect(page).to have_no_css("[data-post-number='4']")
    expect(page).to have_no_css(".post__topic-map.--op", visible: :visible)

    expect(toggle).to have_show_comments_button(count: 3)

    toggle.click_toggle

    expect(page).to have_css("[data-post-number='2']")
    expect(page).to have_css("[data-post-number='3']")
    expect(page).to have_css("[data-post-number='4']")

    expect(toggle).to have_hide_comments_button

    toggle.click_toggle

    expect(page).to have_no_css("[data-post-number='2']")
    expect(page).to have_no_css("[data-post-number='3']")
    expect(page).to have_no_css("[data-post-number='4']")

    toggle.click_toggle

    expect(page).to have_css("[data-post-number='2']")
    expect(page).to have_css("[data-post-number='3']")
    expect(page).to have_css("[data-post-number='4']")

    expect(toggle).to have_hide_comments_button
  end

  it "auto-expands comments when entering on a reply url" do
    visit("#{documentation_topic.relative_url}/#{reply_3.post_number}")

    expect(toggle).to have_hide_comments_button
    expect(page).to have_css("[data-post-number='2']")
    expect(page).to have_css("[data-post-number='3']")
    expect(page).to have_css("[data-post-number='4']")
  end

  it "resets comments state when navigating between doc topics" do
    topic_page.visit_topic(documentation_topic)

    toggle.click_toggle
    expect(page).to have_css("[data-post-number='2']")

    find(
      ".sidebar-section-link[data-link-name*='#{documentation_topic_2.title.parameterize}']",
    ).click

    expect(page).to have_css("h1 .fancy-title", text: documentation_topic_2.title)
    expect(page).to have_no_css("[data-post-number='2']")
    expect(toggle).to have_show_comments_button(count: 1)
  end

  it "simplifies the topic list for doc categories" do
    visit("/c/#{documentation_category.slug}/#{documentation_category.id}")

    expect(page).to have_css(".topic-list.doc-simple-mode")
    expect(page).to have_no_css(".topic-list .posters")
    expect(page).to have_no_css(".topic-list .replies")
    expect(page).to have_css(".topic-list th", text: "Updated")
  end

  it "does not simplify the topic list for non-doc categories" do
    visit("/c/#{category.slug}/#{category.id}")

    expect(page).to have_no_css(".topic-list.doc-simple-mode")
    expect(page).to have_css(".topic-list .posters")
  end

  it "does not affect non-doc categories" do
    regular_topic = Fabricate(:topic_with_op, category: category)
    Fabricate(:post, topic: regular_topic, raw: "A reply in a regular topic")

    topic_page.visit_topic(regular_topic)

    expect(page).to have_css("[data-post-number='1']")
    expect(page).to have_css("[data-post-number='2']")
    expect(toggle).to have_no_toggle
  end

  it "does not apply when setting is disabled" do
    SiteSetting.doc_categories_simple_mode = false

    topic_page.visit_topic(documentation_topic)

    expect(page).to have_css("[data-post-number='1']")
    expect(page).to have_css("[data-post-number='2']")
    expect(toggle).to have_no_toggle
  end
end
