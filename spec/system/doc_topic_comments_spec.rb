# frozen_string_literal: true

RSpec.describe "Doc topic comments", system: true do
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:documentation_topic) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:reply_post_one) { Fabricate(:post, topic: documentation_topic) }
  fab!(:reply_post_two) { Fabricate(:post, topic: documentation_topic) }

  let(:topic_page) { PageObjects::Pages::Topic.new }

  before do
    SiteSetting.doc_categories_enabled = true

    index_topic = Fabricate(:topic, category: documentation_category)
    Fabricate(:post, topic: index_topic, raw: <<~MD)
      ## Documentation Index
      * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
    MD

    documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
    documentation_category.save!

    Site.clear_cache
    Topic.clear_doc_categories_cache
  end

  def visit_doc_topic
    topic_page.visit_topic(documentation_topic)
    expect(page).to have_css("body.doc-topic-comments", wait: 5)
  end

  it "collapses replies behind the comments panel by default" do
    visit_doc_topic

    expect(page).to have_css("body.doc-topic-comments.doc-topic-comments--collapsed")
    expected_summary =
      I18n.t(
        "js.doc_categories.comments.collapsed_summary",
        count: documentation_topic.reload.posts_count - 1,
      )
    expect(page).to have_css(".doc-topic-comments-panel__summary", text: expected_summary)
    expect(page).to have_css(".topic-post[data-post-number='1']", visible: :visible)
    expect(page).to have_no_css(".topic-post[data-post-number='2']", visible: :visible)
    expect(page).to have_no_css(".topic-post[data-post-number='3']", visible: :visible)
    expect(page).to have_no_css(".topic-navigation", visible: :visible)
  end

  it "reveals replies when readers expand the comments panel" do
    visit_doc_topic

    click_button I18n.t("js.doc_categories.comments.expand")

    expect(page).to have_no_css("body.doc-topic-comments.doc-topic-comments--collapsed")
    expect(page).to have_css(".topic-post[data-post-number='2']", visible: :visible)
    expect(page).to have_css(".topic-post[data-post-number='3']", visible: :visible)
    expect(page).to have_button(I18n.t("js.doc_categories.comments.collapse"))
    expect(page).to have_text(I18n.t("js.doc_categories.comments.expanded_hint"))
    expect(page).to have_css(".topic-navigation", visible: :visible)
  end
end
