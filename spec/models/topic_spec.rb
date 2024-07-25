# frozen_string_literal: true

require "rails_helper"

describe Topic do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:topic) { Fabricate(:topic, category: category) }
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

  before do
    SiteSetting.doc_categories_enabled = true

    documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
    documentation_category.save!
  end

  context "when changing the topic category" do
    it "doesn't invalidate cache if the topic category wasn't changed" do
      described_class.expects(:clear_doc_categories_cache).never

      index_topic.title = "This is just a test"
      index_topic.save!
    end

    it "doesn't invalidate the cache if the topic is not the index in a doc category" do
      described_class.expects(:clear_doc_categories_cache).never

      documentation_topic.change_category_to_id(category.id)
      documentation_topic.save!

      topic.change_category_to_id(documentation_category.id)
      topic.save!
    end

    it "invalidates the cache if the index topic is moved FROM another category" do
      documentation_category.custom_fields["doc_category_index_topic"] = topic.id
      documentation_category.save!

      described_class.expects(:clear_doc_categories_cache).once
      topic.change_category_to_id(documentation_category.id)
      topic.save!
    end

    it "publishes the category via message bus when the index topic is moved FROM another category" do
      index_topic.change_category_to_id(category.id)
      index_topic.save!

      messages =
        MessageBus.track_publish("/categories") do
          index_topic.change_category_to_id(documentation_category.id)
          index_topic.save!
        end

      expect(messages.length).to eq(1)
      message = messages.first

      category_hash = message.data[:categories].first

      expect(category_hash[:id]).to eq(documentation_category.id)
      expect(category_hash.has_key?(:doc_category_index)).to eq(true)

      doc_category_index = category_hash[:doc_category_index]
      expect(doc_category_index).to be_present
      expect(doc_category_index.size).to eq(2)
      expect(doc_category_index[0]["links"].size).to eq(2)
      expect(doc_category_index[1]["links"].size).to eq(2)
    end

    it "invalidates the cache if the index topic is moved TO another category" do
      described_class.expects(:clear_doc_categories_cache).once
      index_topic.change_category_to_id(category.id)
      index_topic.save!
    end

    it "publishes the category via message bus when the index topic is moved TO another category" do
      messages =
        MessageBus.track_publish("/categories") do
          index_topic.change_category_to_id(category.id)
          index_topic.save!
        end

      expect(messages.length).to eq(1)
      message = messages.first

      category_hash = message.data[:categories].first

      expect(category_hash[:id]).to eq(documentation_category.id)
      expect(category_hash.has_key?(:doc_category_index)).to eq(false)
    end
  end

  context "when deleting a topic" do
    it "invalidates the cache if the index topic is deleted" do
      described_class.expects(:clear_doc_categories_cache).once
      index_topic.trash!
    end

    it "doesn't invalidate the cache if another topic is deleted" do
      described_class.expects(:clear_doc_categories_cache).never
      documentation_topic.trash!
    end
  end

  context "when recovering a topic" do
    it "invalidates the cache if the index topic is recovered" do
      index_topic.trash!

      described_class.expects(:clear_doc_categories_cache).once
      index_topic.recover!
    end

    it "doesn't invalidate the cache if another topic is deleted" do
      documentation_topic.trash!

      described_class.expects(:clear_doc_categories_cache).never
      documentation_topic.recover!
    end
  end
end
