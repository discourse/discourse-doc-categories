# frozen_string_literal: true

describe DocCategories::Initializers::HandlePostChanges do
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:other_category) { Fabricate(:category_with_definition) }
  fab!(:index_topic) do
    Fabricate(:topic, category: documentation_category).tap { |topic| Fabricate(:post, topic:) }
  end
  fab!(:other_topic) do
    Fabricate(:topic, category: other_category).tap { |topic| Fabricate(:post, topic:) }
  end

  let!(:doc_index) do
    Fabricate(:doc_categories_index, category: documentation_category, index_topic:)
  end

  before do
    SiteSetting.doc_categories_enabled = true
    Jobs::DocCategoriesRefreshIndex.jobs.clear
  end

  def revise(post, topic = post.topic, **attributes)
    PostRevisor.new(post, topic).revise!(post.user, attributes)
  end

  it "clears the cache and republishes the doc category when the index post cooked changes" do
    expect_enqueued_with(
      job: :doc_categories_refresh_index,
      args: {
        category_id: documentation_category.id,
      },
    ) { revise(index_topic.first_post, raw: index_topic.first_post.raw + "\nUpdated") }
  end

  it "does not clear the cache for edits outside the doc index" do
    expect_not_enqueued_with(job: :doc_categories_refresh_index) do
      revise(other_topic.first_post, raw: "Changed")
    end
  end

  it "clears the index and refreshes the index's category when the index topic moves" do
    Jobs.run_immediately!
    revise(index_topic.first_post, category_id: other_category.id)

    expect(DocCategories::Index.exists?(category_id: documentation_category.id)).to eq(false)
    # topic *should not* be the new category's index topic
    expect(
      DocCategories::Index.exists?(category_id: other_category.id, index_topic_id: index_topic.id),
    ).to eq(false)
  end
end
