# frozen_string_literal: true

require "rails_helper"

describe BasicCategorySerializer do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:documentation_subcategory) do
    Fabricate(:category_with_definition, parent_category_id: documentation_category.id)
  end
  fab!(:empty_documentation_topic) do
    t = Fabricate(:topic, category: documentation_category)
    Fabricate(:post, topic: t, raw: "A topic with no links")
    t
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
    Fabricate(:post, topic: t)
    t
  end

  fab!(:documentation_index) do
    index = Fabricate(:doc_categories_index, category: documentation_category, index_topic:)
    index
      .sidebar_sections
      .create!(position: 0, title: "General Usage")
      .tap do |section|
        section.sidebar_links.create!(
          position: 0,
          title: documentation_topic.title,
          href: "/t/#{documentation_topic.slug}/#{documentation_topic.id}",
        )
        section.sidebar_links.create!(
          position: 1,
          title: documentation_topic2.slug,
          href: "/t/#{documentation_topic2.slug}/#{documentation_topic2.id}",
        )
      end
    index
      .sidebar_sections
      .create!(position: 1, title: "Writing")
      .tap do |section|
        section.sidebar_links.create!(
          position: 0,
          title: documentation_topic3.title,
          href: "/t/#{documentation_topic3.slug}/#{documentation_topic3.id}",
        )
        section.sidebar_links.create!(
          position: 1,
          title: documentation_topic4.slug,
          href: "/t/#{documentation_topic4.slug}/#{documentation_topic4.id}",
        )
      end
    index
  end

  before { SiteSetting.doc_categories_enabled = true }

  describe "#doc_category_index" do
    it "isn't serialized if the category is not a doc category" do
      data = described_class.new(category, root: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't exist" do
      documentation_index.update_columns(index_topic_id: 0)
      documentation_category.reload

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't belong to the category" do
      index_topic.update!(category: category)
      documentation_category.reload

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't belongs to a subcategory" do
      index_topic.update!(category: documentation_subcategory)
      documentation_category.reload

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the index topic doesn't contain a first post" do
      empty_topic = Fabricate(:topic, category: documentation_category)

      documentation_index.update!(index_topic: empty_topic)
      documentation_category.reload

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "isn't serialized if the topic index has no sections" do
      documentation_index.update!(index_topic: empty_documentation_topic)
      documentation_category.reload

      data = described_class.new(category, documentation_category: false).as_json
      expect(data.has_key?(:doc_category_index)).to eq(false)
    end

    it "is serialized as expected if the index topic can be parsed" do
      data = described_class.new(documentation_category, root: false).as_json

      parsed_index = data[:doc_category_index]
      expect(parsed_index.size).to eq(2)

      expect(parsed_index[0]["text"]).to eq("General Usage")
      expect(parsed_index[0]["links"].size).to eq(2)
      expect(parsed_index[0]["links"][0]).to eq(
        {
          text: documentation_topic.title,
          href: "/t/#{documentation_topic.slug}/#{documentation_topic.id}",
        }.as_json,
      )
      expect(parsed_index[0]["links"][1]).to eq(
        {
          text: documentation_topic2.slug,
          href: "/t/#{documentation_topic2.slug}/#{documentation_topic2.id}",
        }.as_json,
      )

      expect(parsed_index[1]["text"]).to eq("Writing")
      expect(parsed_index[1]["links"].size).to eq(2)
      expect(parsed_index[1]["links"][0]).to eq(
        {
          text: documentation_topic3.title,
          href: "/t/#{documentation_topic3.slug}/#{documentation_topic3.id}",
        }.as_json,
      )
      expect(parsed_index[1]["links"][1]).to eq(
        {
          text: documentation_topic4.slug,
          href: "/t/#{documentation_topic4.slug}/#{documentation_topic4.id}",
        }.as_json,
      )
    end
  end
end
