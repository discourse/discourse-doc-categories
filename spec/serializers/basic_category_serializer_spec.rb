# frozen_string_literal: true

require "rails_helper"

describe BasicCategorySerializer do
  fab!(:category) { Fabricate(:category_with_definition) }
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

  context "#doc_category_index" do
    it "isn't serialized if the category is not a doc category" do
      data = described_class.new(category, root: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't exist" do
      index = DocCategories::Index.find_by!(category_id: documentation_category.id)
      index.update_columns(index_topic_id: 0)
      index.sidebar_sections.destroy_all

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't belong to the category" do
      index_topic.category_id = category.id
      index_topic.save!

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't belongs to a subcategory" do
      index_topic.category_id = documentation_subcategory.id
      index_topic.save!

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't contain a first post" do
      topic_without_posts = Fabricate(:topic, category: documentation_category)
      DocCategories::CategoryIndexManager.new(documentation_category).assign!(
        topic_without_posts.id,
      )

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't contain the expected document structure to be parsed" do
      DocCategories::CategoryIndexManager.new(documentation_category).assign!(
        documentation_topic.id,
      )

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "is serialized as expected if the index topic can be parsed" do
      data = described_class.new(documentation_category, root: false).as_json

      parsed_index = data[:doc_category_index]
      expect(parsed_index).to be_present

      expect(parsed_index.size).to eq(2)

      expect(parsed_index[0]["text"]).to eq("General Usage")
      expect(parsed_index[0]["links"].size).to eq(2)
      expect(parsed_index[0]["links"][0]).to include(
        "text" => documentation_topic.title,
        "href" => "/t/#{documentation_topic.slug}/#{documentation_topic.id}",
        "topic_id" => documentation_topic.id,
      )
      expect(parsed_index[0]["links"][1]).to include(
        "text" => documentation_topic2.slug,
        "href" => "/t/#{documentation_topic2.slug}/#{documentation_topic2.id}",
        "topic_id" => documentation_topic2.id,
      )

      expect(parsed_index[1]["text"]).to eq("Writing")
      expect(parsed_index[1]["links"].size).to eq(2)
      expect(parsed_index[1]["links"][0]).to include(
        "text" => documentation_topic3.title,
        "href" => "/t/#{documentation_topic3.slug}/#{documentation_topic3.id}",
        "topic_id" => documentation_topic3.id,
      )
      expect(parsed_index[1]["links"][1]).to include(
        "text" => documentation_topic4.slug,
        "href" => "/t/#{documentation_topic4.slug}/#{documentation_topic4.id}",
        "topic_id" => documentation_topic4.id,
      )
    end
  end
end
