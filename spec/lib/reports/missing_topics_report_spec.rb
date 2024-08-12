# frozen_string_literal: true

require "rails_helper"

RSpec.describe ::DocCategories::Reports::MissingTopicsReport do
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

  describe "doc_categories_missing_topics" do
    def report(opts = {})
      Report.find("doc_categories_missing_topics", opts)
    end

    before do
      SiteSetting.doc_categories_enabled = true

      documentation_category.custom_fields[DocCategories::CATEGORY_INDEX_TOPIC] = index_topic.id
      documentation_category.save!
    end

    it "returns the expected data" do
      other_topic = Fabricate(:topic, category: documentation_category)

      generated_report = report(filters: { doc_category: documentation_category.id })

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      expect(generated_report.data).to match_array(
        [
          { id: documentation_category.topic.id, title: documentation_category.topic.title },
          { id: other_topic.id, title: other_topic.title },
        ],
      )
    end

    it "doesn't include unlisted topics in the results" do
      invisible_topic = Fabricate(:topic, category: documentation_category, visible: false)

      generated_report = report(filters: { doc_category: documentation_category.id })

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      expect(generated_report.data).not_to include(
        [{ id: invisible_topic.id, title: invisible_topic.title }],
      )
    end

    it "can include topics from subcategories" do
      generated_report =
        report(
          filters: {
            doc_category: documentation_category.id,
            include_topic_from_subcategories: true,
          },
        )

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters[:include_topic_from_subcategories]).to eq(true)

      expect(generated_report.data).to match_array(
        [
          { id: documentation_category.topic.id, title: documentation_category.topic.title },
          { id: topic_in_subcategory.id, title: topic_in_subcategory.title },
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
