# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::DocCategories::Reports::ExtraneousItemsReport do
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

      documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
      documentation_category.save!
    end

    it "returns the expected data when excluding topics from subcategories" do
      generated_report = report(filters: { doc_category: documentation_category.id })

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      expect(generated_report.data).to match_array(
        [
          {
            title: documentation_subtopic.title,
            href: "/t/#{documentation_subtopic.slug}/#{documentation_subtopic.id}",
            reason: :other_category,
          },
          {
            title: documentation_subtopic2.slug,
            href: "/t/#{documentation_subtopic2.slug}/#{documentation_subtopic2.id}",
            reason: :other_category,
          },
          { title: topic.title, href: "/t/#{topic.slug}/#{topic.id}", reason: :other_category },
          { title: "Category", href: "/c/#{category.slug}/#{category.id}", reason: :not_a_topic },
          {
            title: "Meta topic",
            href: "https://meta.discourse.org/t/using-discourse-index/308031",
            reason: :external,
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
          { title: topic.title, href: "/t/#{topic.slug}/#{topic.id}", reason: :other_category },
          { title: "Category", href: "/c/#{category.slug}/#{category.id}", reason: :not_a_topic },
          {
            title: "Meta topic",
            href: "https://meta.discourse.org/t/using-discourse-index/308031",
            reason: :external,
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
