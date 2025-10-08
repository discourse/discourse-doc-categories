# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::DocCategories::Reports::ExtraneousItemsReport do
  fab!(:category, :category_with_definition)
  fab!(:documentation_category, :category_with_definition)
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
  fab!(:documentation_invisible_topic) do
    t = Fabricate(:topic, category: documentation_category, visible: false)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:documentation_subtopic) do
    t = Fabricate(:topic, category: documentation_subcategory)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:documentation_subtopic2) do
    t = Fabricate(:topic, category: documentation_subcategory)
    Fabricate(:post, topic: t)
    t
  end
  fab!(:topic) { Fabricate(:topic, category:) }
  fab!(:index_topic) do
    t = Fabricate(:topic, category: documentation_category)

    Fabricate(:post, topic: t, raw: <<~MD)
      Lorem ipsum dolor sit amet

      ## General Usage

      * No link
      * [#{documentation_topic.title}](/t/#{documentation_topic.slug}/#{documentation_topic.id})
      * #{documentation_topic2.slug}: [#{documentation_topic2.title}](/t/#{documentation_topic2.slug}/#{documentation_topic2.id})
      * [#{documentation_invisible_topic.title}](/t/#{documentation_invisible_topic.slug}/#{documentation_invisible_topic.id})

      ## Writing

      * [#{documentation_subtopic.title}](/t/#{documentation_subtopic.slug}/#{documentation_subtopic.id})
      * #{documentation_subtopic2.slug}: [#{documentation_subtopic2.title}](/t/#{documentation_subtopic2.slug}/#{documentation_subtopic2.id})
      * No link

      ## Others
      * [#{topic.title}](/t/#{topic.slug}/#{topic.id})
      * [Category](/c/#{category.slug}/#{category.id})

      ## External links
      * [Meta topic](https://meta.discourse.org/t/using-discourse-index/308031)


    MD

    t
  end
  fab!(:topic_in_subcategory) do
    t = Fabricate(:topic, category: documentation_subcategory)
    Fabricate(:post, topic: t)
    t
  end

  describe "doc_categories_extraneous_items" do
    def report(opts = {})
      Report.find("doc_categories_extraneous_items", opts)
    end

    before do
      SiteSetting.doc_categories_enabled = true

      Jobs.with_immediate_jobs do
        DocCategories::CategoryIndexManager.new(documentation_category).assign!(index_topic.id)
      end
    end

    it "returns the expected data when excluding topics from subcategories" do
      generated_report = report(filters: { doc_category: documentation_category.id })

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      expect(generated_report.data).to match_array(
        [
          {
            title: documentation_invisible_topic.title,
            href: "/t/#{documentation_invisible_topic.slug}/#{documentation_invisible_topic.id}",
            reason: :topic_not_visible,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: documentation_subtopic.title,
            href: "/t/#{documentation_subtopic.slug}/#{documentation_subtopic.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: documentation_subtopic2.slug,
            href: "/t/#{documentation_subtopic2.slug}/#{documentation_subtopic2.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: topic.title,
            href: "/t/#{topic.slug}/#{topic.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: "Category",
            href: "/c/#{category.slug}/#{category.id}",
            reason: :not_a_topic,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: "Meta topic",
            href: "https://meta.discourse.org/t/using-discourse-index/308031",
            reason: :external,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
        ],
      )
    end

    it "returns the expected data when including topics from subcategories" do
      generated_report =
        report(
          filters: {
            doc_category: documentation_category.id,
            include_topic_from_subcategories: true,
          },
        )

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(true)

      expect(generated_report.data).to match_array(
        [
          {
            title: documentation_invisible_topic.title,
            href: "/t/#{documentation_invisible_topic.slug}/#{documentation_invisible_topic.id}",
            reason: :topic_not_visible,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: topic.title,
            href: "/t/#{topic.slug}/#{topic.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: "Category",
            href: "/c/#{category.slug}/#{category.id}",
            reason: :not_a_topic,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: "Meta topic",
            href: "https://meta.discourse.org/t/using-discourse-index/308031",
            reason: :external,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
        ],
      )
    end

    it "returns the expected data when filtering all categories" do
      other_category = Fabricate(:category_with_definition, name: "The other category")
      other_category_index_topic =
        Fabricate(:topic, category: other_category).tap do |t|
          Fabricate(:post, topic: t, raw: index_topic.first_post.raw)
        end

      Jobs.with_immediate_jobs do
        DocCategories::CategoryIndexManager.new(other_category).assign!(
          other_category_index_topic.id,
        )
      end

      generated_report = report(filters: { doc_category: -1 })

      expect(generated_report.filters[:doc_category]).to eq(-1)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      grouped = generated_report.data.group_by { |row| row[:index_category_id] }

      expect(grouped.keys).to contain_exactly(documentation_category.id, other_category.id)

      expect(grouped[documentation_category.id]).to match_array(
        [
          {
            title: documentation_invisible_topic.title,
            href: "/t/#{documentation_invisible_topic.slug}/#{documentation_invisible_topic.id}",
            reason: :topic_not_visible,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: documentation_subtopic.title,
            href: "/t/#{documentation_subtopic.slug}/#{documentation_subtopic.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: documentation_subtopic2.slug,
            href: "/t/#{documentation_subtopic2.slug}/#{documentation_subtopic2.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: topic.title,
            href: "/t/#{topic.slug}/#{topic.id}",
            reason: :other_category,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: "Category",
            href: "/c/#{category.slug}/#{category.id}",
            reason: :not_a_topic,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            title: "Meta topic",
            href: "https://meta.discourse.org/t/using-discourse-index/308031",
            reason: :external,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
        ],
      )

      expect(grouped[other_category.id]).to match_array(
        [
          {
            title: documentation_topic.title,
            href: "/t/#{documentation_topic.slug}/#{documentation_topic.id}",
            reason: :other_category,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: documentation_topic2.slug,
            href: "/t/#{documentation_topic2.slug}/#{documentation_topic2.id}",
            reason: :other_category,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: documentation_invisible_topic.title,
            href: "/t/#{documentation_invisible_topic.slug}/#{documentation_invisible_topic.id}",
            reason: :other_category,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: documentation_subtopic.title,
            href: "/t/#{documentation_subtopic.slug}/#{documentation_subtopic.id}",
            reason: :other_category,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: documentation_subtopic2.slug,
            href: "/t/#{documentation_subtopic2.slug}/#{documentation_subtopic2.id}",
            reason: :other_category,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: topic.title,
            href: "/t/#{topic.slug}/#{topic.id}",
            reason: :other_category,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: "Category",
            href: "/c/#{category.slug}/#{category.id}",
            reason: :not_a_topic,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
          {
            title: "Meta topic",
            href: "https://meta.discourse.org/t/using-discourse-index/308031",
            reason: :external,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
        ],
      )
    end

    it "doesn't return data for a regular category" do
      generated_report = report(filters: { doc_category: category.id })

      expect(generated_report.filters[:doc_category]).to eq(category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      expect(generated_report.data).to be_blank
    end
  end
end
