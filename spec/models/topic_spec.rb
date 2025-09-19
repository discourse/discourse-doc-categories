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
    Jobs.run_immediately!
    SiteSetting.doc_categories_enabled = true

    DocCategories::CategoryIndexManager.new(documentation_category).assign!(index_topic.id)
  end

  def doc_index_for(category)
    DocCategories::Index.find_by(category_id: category.id)
  end

  def sidebar_links_for(category)
    DocCategories::SidebarLink
      .joins(sidebar_section: :index)
      .where(doc_categories_indexes: { category_id: category.id })
      .order("doc_categories_sidebar_sections.position", :position)
      .pluck(:topic_id)
  end

  context "when changing the topic category" do
    it "doesn't change the doc index when an unrelated topic moves between categories" do
      original_links = sidebar_links_for(documentation_category)

      topic.change_category_to_id(documentation_category.id)
      topic.save!

      expect(sidebar_links_for(documentation_category)).to eq(original_links)
    end

    it "removes the doc index when the index topic is moved to another category" do
      index_topic.change_category_to_id(category.id)
      index_topic.save!

      expect(doc_index_for(documentation_category)).to be_nil
    end

    it "restores the doc index when the index topic is moved back into the category" do
      index_topic.change_category_to_id(category.id)
      index_topic.save!

      expect(doc_index_for(documentation_category)).to be_nil

      index_topic.change_category_to_id(documentation_category.id)
      index_topic.save!

      expect(doc_index_for(documentation_category)).to be_present
      expect(sidebar_links_for(documentation_category)).to include(
        documentation_topic.id,
        documentation_topic2.id,
        documentation_topic3.id,
        documentation_topic4.id,
      )
    end

    it "removes links to topics that are moved out of the doc category" do
      expect(sidebar_links_for(documentation_category)).to include(documentation_topic.id)

      documentation_topic.change_category_to_id(category.id)
      documentation_topic.save!

      expect(sidebar_links_for(documentation_category)).not_to include(documentation_topic.id)
    end

    it "publishes the category via message bus when the index topic is moved" do
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

      messages =
        MessageBus.track_publish("/categories") do
          index_topic.change_category_to_id(documentation_category.id)
          index_topic.save!
        end

      expect(messages.length).to be >= 1
      category_hash = messages.last.data[:categories].first

      expect(category_hash[:id]).to eq(documentation_category.id)
      expect(category_hash[:doc_category_index]).to be_present
    end
  end

  context "when deleting a topic" do
    it "removes the doc index if the index topic is trashed" do
      index_topic.trash!

      expect(doc_index_for(documentation_category)).to be_nil
    end

    it "doesn't change the doc index if an unrelated topic is trashed" do
      original_links = sidebar_links_for(documentation_category)

      documentation_topic4.trash!

      expect(sidebar_links_for(documentation_category)).to eq(original_links)
    end

    it "removes links to trashed topics" do
      expect(sidebar_links_for(documentation_category)).to include(documentation_topic.id)

      documentation_topic.trash!

      expect(sidebar_links_for(documentation_category)).not_to include(documentation_topic.id)
    end
  end

  context "when recovering a topic" do
    it "rebuilds the doc index when the index topic is recovered" do
      index_topic.trash!

      index_topic.recover!

      expect(doc_index_for(documentation_category)).to be_present
      expect(sidebar_links_for(documentation_category)).to include(documentation_topic.id)
    end

    it "doesn't change the doc index if another topic is recovered" do
      documentation_topic.trash!

      documentation_topic.recover!

      expect(sidebar_links_for(documentation_category)).to include(documentation_topic.id)
    end
  end
end
