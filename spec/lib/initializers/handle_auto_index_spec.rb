# frozen_string_literal: true

describe DocCategories::Initializers::HandleAutoIndex do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:index) do
    Fabricate(
      :doc_categories_index,
      category: category,
      index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
    )
  end
  fab!(:auto_section) do
    Fabricate(
      :doc_categories_sidebar_section,
      index: index,
      auto_index: true,
      title: "Topics",
      position: 0,
    )
  end
  fab!(:topic) { Fabricate(:topic, category: category) }

  before do
    SiteSetting.doc_categories_enabled = true
    Jobs::DocCategoriesAutoIndex.jobs.clear
  end

  describe "visibility changes" do
    it "enqueues an add job when a topic becomes visible" do
      topic.update!(visible: false)
      Jobs::DocCategoriesAutoIndex.jobs.clear

      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "add",
          topic_id: topic.id,
        },
      ) { topic.update_status("visible", true, admin) }
    end

    it "enqueues a remove job when a topic becomes invisible" do
      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "remove",
          topic_id: topic.id,
        },
      ) { topic.update_status("visible", false, admin) }
    end

    it "does not enqueue a job for non-visibility status changes" do
      expect_not_enqueued_with(job: :doc_categories_auto_index) do
        topic.update_status("closed", true, admin)
      end
    end
  end

  describe "archetype changes" do
    it "enqueues a remove job when a topic is made a banner" do
      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "remove",
          topic_id: topic.id,
        },
      ) { topic.make_banner!(admin) }
    end

    it "enqueues an add job when a banner is removed" do
      topic.update_columns(archetype: Archetype.banner)

      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "add",
          topic_id: topic.id,
        },
      ) { topic.remove_banner!(admin) }
    end

    it "enqueues a remove job when a topic is converted to a PM" do
      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "remove",
          topic_id: topic.id,
        },
      ) { topic.update!(archetype: Archetype.private_message, category_id: nil) }
    end

    it "enqueues an add job when a PM is converted to a regular topic" do
      topic.update_columns(archetype: Archetype.private_message, category_id: nil)

      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "add",
          topic_id: topic.id,
        },
      ) { topic.update!(archetype: Archetype.default, category_id: category.id) }
    end
  end
end
