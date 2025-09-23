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

  let!(:doc_index) do
    Fabricate(:doc_categories_index, category: documentation_category, index_topic: index_topic)
  end

  before do
    SiteSetting.doc_categories_enabled = true
    Jobs::DocCategoriesRefreshIndex.jobs.clear
  end

  it "assigns and refreshes when the index topic is trashed" do
    expect_enqueued_with(
      job: :doc_categories_refresh_index,
      args: {
        category_id: documentation_category.id,
      },
    ) { index_topic.trash! }

    expect(DocCategories::Index.exists?(category_id: documentation_category.id)).to eq(false)
  end

  it "does nothing when another topic is trashed" do
    expect_not_enqueued_with(job: :doc_categories_refresh_index) { other_topic.trash! }

    expect(DocCategories::Index.exists?(category_id: documentation_category.id)).to eq(true)
  end

  it "reassigns the index when the topic is recovered" do
    index_topic.trash!
    expect(DocCategories::Index.exists?(category_id: documentation_category.id)).to eq(false)
    Jobs::DocCategoriesRefreshIndex.jobs.clear

    expect_enqueued_with(
      job: :doc_categories_refresh_index,
      args: {
        category_id: documentation_category.id,
      },
    ) { index_topic.recover! }

    expect(
      DocCategories::Index.exists?(
        category_id: documentation_category.id,
        index_topic_id: index_topic.id,
      ),
    ).to eq(true)
  end
end
