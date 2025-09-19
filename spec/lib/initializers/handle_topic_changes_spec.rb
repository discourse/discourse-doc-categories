# frozen_string_literal: true

describe DocCategories::Initializers::HandleTopicChanges do
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:index_topic) do
    Fabricate(:topic, category: documentation_category).tap do |topic|
      Fabricate(:post, topic: topic)
    end
  end
  fab!(:other_topic) do
    Fabricate(:topic, category: documentation_category).tap do |topic|
      Fabricate(:post, topic: topic)
    end
  end

  before do
    SiteSetting.doc_categories_enabled = true

    documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
    documentation_category.save!
  end

  it "clears the cache and republishes the doc category when the index topic is trashed" do
    Topic.expects(:clear_doc_categories_cache).once

    messages = MessageBus.track_publish("/categories") { index_topic.trash! }

    category_ids = messages.flat_map { |message| message.data[:categories].map { |c| c[:id] } }

    expect(category_ids).to include(documentation_category.id)
  end

  it "publishes the category without clearing the doc cache when another topic is trashed" do
    Topic.expects(:clear_doc_categories_cache).never

    messages = MessageBus.track_publish("/categories") { other_topic.trash! }

    category_ids = messages.flat_map { |message| message.data[:categories].map { |c| c[:id] } }

    expect(category_ids).to include(documentation_category.id)
  end

  it "clears the cache when the index topic is recovered" do
    index_topic.trash!

    Topic.expects(:clear_doc_categories_cache).once

    messages = MessageBus.track_publish("/categories") { index_topic.recover! }

    category_ids = messages.flat_map { |message| message.data[:categories].map { |c| c[:id] } }

    expect(category_ids).to include(documentation_category.id)
  end
end
