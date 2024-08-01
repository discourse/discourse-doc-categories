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
    SiteSetting.doc_categories_enabled = true

    documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
    documentation_category.save!
  end

  it "doesn't invalidate the cache when the post is not the first of the topic" do
    described_class.expects(:clear_doc_categories_cache).never

    second_index_post.raw = "Just a test"
    second_index_post.save!
  end

  it "doesn't invalidate the cache when the cooked text doesn't change" do
    described_class.expects(:clear_doc_categories_cache).never

    index_topic.first_post.user_id = Fabricate(:user).id
    index_topic.first_post.save!
  end

  it "doesn't invalidate the cache when the topic doesn't belong to a category" do
    index_topic.change_category_to_id(nil)
    index_topic.save!

    described_class.expects(:clear_doc_categories_cache).never

    index_topic.first_post.raw = "This is a test"
    index_topic.first_post.save!
  end

  it "doesn't invalidate the cache when the topic doesn't belong to a doc category" do
    described_class.expects(:clear_doc_categories_cache).never

    topic.first_post.raw = "This is a test"
    topic.first_post.save!
  end

  it "doesn't invalidate the cache when the topic isn't the index topic of the doc category" do
    described_class.expects(:clear_doc_categories_cache).never

    documentation_topic.first_post.raw = "This is a test"
    documentation_topic.first_post.save!
  end

  it "invalidates the cache when the cooked text of the first post in the index topic is updated" do
    described_class.expects(:clear_doc_categories_cache).once

    index_topic.first_post.raw = "This is a test"
    index_topic.first_post.save!
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
