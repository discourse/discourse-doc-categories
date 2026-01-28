# frozen_string_literal: true

RSpec.describe ::DocCategories::Reports::MissingTopicsReport do
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

      Jobs.with_immediate_jobs do
        DocCategories::CategoryIndexManager.new(documentation_category).assign!(index_topic.id)
      end
    end

    it "returns the expected data" do
      other_topic = Fabricate(:topic, category: documentation_category)

      generated_report = report(filters: { doc_category: documentation_category.id })

      expect(generated_report.filters[:doc_category]).to eq(documentation_category.id)
      expect(generated_report.filters.has_key?(:include_topic_from_subcategories)).to eq(false)

      expect(generated_report.data).to match_array(
        [
          {
            id: documentation_category.topic.id,
            title: documentation_category.topic.title,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            id: other_topic.id,
            title: other_topic.title,
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

      extra_topic = Fabricate(:topic, category: documentation_category)

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
            id: documentation_category.topic.id,
            title: documentation_category.topic.title,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            id: extra_topic.id,
            title: extra_topic.title,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
        ],
      )

      expect(grouped[other_category.id]).to match_array(
        [
          {
            id: other_category.topic.id,
            title: other_category.topic.title,
            index_category_id: other_category.id,
            index_category_name: other_category.name,
            index_category_url: "/c/#{other_category.id}",
          },
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
          {
            id: documentation_category.topic.id,
            title: documentation_category.topic.title,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
          },
          {
            id: topic_in_subcategory.id,
            title: topic_in_subcategory.title,
            index_category_id: documentation_category.id,
            index_category_name: documentation_category.name,
            index_category_url: "/c/#{documentation_category.id}",
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
