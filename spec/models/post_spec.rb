# frozen_string_literal: true

require "rails_helper"

describe Post do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:topic) do
    t = Fabricate(:topic, category: category)
    Fabricate(:post, topic: t)
    t
  end

  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:documentation_subcategory) do
    Fabricate(:category_with_definition, parent_category_id: documentation_category.id)
  end
  fab!(:documentation_topic) do
    t = Fabricate(:topic, category: documentation_category)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:documentation_topic2) do
    t = Fabricate(:topic, category: documentation_category)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:documentation_topic3) do
    t = Fabricate(:topic, category: documentation_category)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:documentation_topic4) do
    t = Fabricate(:topic, category: documentation_category)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:index_topic) do
    t = Fabricate(:topic, category: documentation_category)

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

    t
  end
  fab!(:second_index_post) { Fabricate(:post, topic: index_topic) }

  before do
    Jobs.run_immediately!
    SiteSetting.doc_categories_enabled = true

    DocCategories::CategoryIndexManager.new(documentation_category).assign!(index_topic.id)
  end

  def sidebar_links_for(category)
    DocCategories::SidebarLink
      .joins(sidebar_section: :index)
      .where(doc_categories_indexes: { category_id: category.id })
      .order("doc_categories_sidebar_sections.position", :position)
      .pluck(:title, :href, :topic_id)
  end

  it "doesn't rebuild the index when the post is not the first of the topic" do
    expect {
      second_index_post.update!(raw: "Just a test")
    }.not_to change { sidebar_links_for(documentation_category) }
  end

  it "doesn't rebuild the index when the cooked text doesn't change" do
    original_links = sidebar_links_for(documentation_category)

    index_topic.first_post.update!(raw: index_topic.first_post.raw)

    expect(sidebar_links_for(documentation_category)).to eq(original_links)
  end

  it "doesn't rebuild the index when the topic isn't the doc index" do
    original_links = sidebar_links_for(documentation_category)

    documentation_topic.first_post.update!(raw: "This is a test")

    expect(sidebar_links_for(documentation_category)).to eq(original_links)
  end

  it "updates the stored sidebar links when the index topic is edited" do
    index_topic.first_post.update!(
      raw: <<~MD,
        * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
        * #{documentation_topic2.slug}: [#{documentation_topic2.title}](/t/#{documentation_topic2.slug}/#{documentation_topic2.id})
      MD
    )

    expect(sidebar_links_for(documentation_category)).to eq(
      [
        [documentation_topic.title, "/t/#{documentation_topic.slug}/#{documentation_topic.id}", documentation_topic.id],
        [
          documentation_topic2.slug,
          "/t/#{documentation_topic2.slug}/#{documentation_topic2.id}",
          documentation_topic2.id,
        ],
      ],
    )
  end

  it "publishes the category via message bus when the index topic is updated" do
    messages =
      MessageBus.track_publish("/categories") do
        index_topic.first_post.raw = <<~MD
      * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
      * #{documentation_topic2.slug}: [#{documentation_topic2.title}](/t/#{documentation_topic2.slug}/#{documentation_topic2.id})
    MD
        index_topic.first_post.save!
      end

    expect(messages.length).to eq(1)
    message = messages.first

    category_hash = message.data[:categories].first

    expect(category_hash[:id]).to eq(documentation_category.id)

    doc_category_index = category_hash[:doc_category_index]
    expect(doc_category_index).to be_present
    expect(doc_category_index.size).to eq(1)
    expect(doc_category_index[0]["links"].size).to eq(2)
  end
end
