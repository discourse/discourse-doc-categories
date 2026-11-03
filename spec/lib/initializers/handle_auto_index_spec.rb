# frozen_string_literal: true

describe DocCategories::Initializers::HandleAutoIndex do
  fab!(:admin)
  fab!(:category, :category_with_definition)
  fab!(:other_category, :category_with_definition)
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

  describe "topic lifecycle events" do
    it "enqueues an add job when a topic is created" do
      expect_enqueued_with(job: :doc_categories_auto_index, args: { action: "add" }) do
        PostCreator.create!(
          admin,
          title: "A new topic for auto-indexing",
          raw: "This is the body of the new topic",
          category: category.id,
        )
      end
    end

    it "enqueues an add job when a topic is recovered" do
      topic.trash!
      Jobs::DocCategoriesAutoIndex.jobs.clear

      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "add",
          topic_id: topic.id,
        },
      ) { topic.recover! }
    end

    it "enqueues a remove job when a topic is trashed" do
      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "remove",
          topic_id: topic.id,
        },
      ) { topic.trash! }
    end

    it "enqueues a remove job when a topic is destroyed" do
      post = Fabricate(:post, topic: topic)

      expect_enqueued_with(
        job: :doc_categories_auto_index,
        args: {
          action: "remove",
          topic_id: topic.id,
        },
      ) { PostDestroyer.new(admin, post).destroy }
    end

    it "does not enqueue an add job for topics in categories without auto-index" do
      expect_not_enqueued_with(job: :doc_categories_auto_index) do
        PostCreator.create!(
          admin,
          title: "A topic in a non-doc category",
          raw: "This should not trigger auto-indexing",
          category: other_category.id,
        )
      end
    end

    context "with subcategories" do
      fab!(:subcategory) { Fabricate(:category, parent_category: category) }

      it "enqueues an add job when auto_index_include_subcategories is enabled" do
        index.update!(auto_index_include_subcategories: true)

        expect_enqueued_with(job: :doc_categories_auto_index, args: { action: "add" }) do
          PostCreator.create!(
            admin,
            title: "A topic in a subcategory",
            raw: "This should trigger auto-indexing via parent",
            category: subcategory.id,
          )
        end
      end

      it "does not enqueue an add job when auto_index_include_subcategories is disabled" do
        expect_not_enqueued_with(job: :doc_categories_auto_index) do
          PostCreator.create!(
            admin,
            title: "A topic in a subcategory",
            raw: "This should not trigger auto-indexing",
            category: subcategory.id,
          )
        end
      end
    end
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
