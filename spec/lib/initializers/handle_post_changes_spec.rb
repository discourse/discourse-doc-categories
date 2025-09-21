# frozen_string_literal: true

describe DocCategories::Initializers::HandlePostChanges do
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:other_category) { Fabricate(:category_with_definition) }
  fab!(:index_topic) do
    Fabricate(:topic, category: documentation_category).tap do |topic|
      Fabricate(:post, topic: topic)
    end
  end
  fab!(:other_topic) do
    Fabricate(:topic, category: other_category).tap { |topic| Fabricate(:post, topic: topic) }
  end

  before do
    SiteSetting.doc_categories_enabled = true

    documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
    documentation_category.save!
  end

  def revise(post, topic = post.topic, **attributes)
    PostRevisor.new(post, topic).revise!(post.user, attributes)
  end

  it "clears the cache and republishes the doc category when the index post cooked changes" do
    Site.expects(:clear_cache).once

    messages =
      MessageBus.track_publish("/categories") do
        revise(index_topic.first_post, raw: index_topic.first_post.raw + "\nUpdated")
      end

    category_ids = messages.flat_map { |message| message.data[:categories].map { |c| c[:id] } }

    expect(category_ids).to include(documentation_category.id)
  end

  it "does not clear the cache for edits outside the doc index" do
    Site.expects(:clear_cache).never

    messages =
      MessageBus.track_publish("/categories") { revise(other_topic.first_post, raw: "Changed") }

    expect(messages).to be_empty
  end

  it "clears the cache when the index topic leaves the doc category" do
    Site.expects(:clear_cache).once

    messages =
      MessageBus.track_publish("/categories") do
        revise(index_topic.first_post, category_id: other_category.id)
      end

    category_ids = messages.flat_map { |message| message.data[:categories].map { |c| c[:id] } }

    expect(category_ids).to include(documentation_category.id)
  end
end
