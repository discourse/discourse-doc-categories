# frozen_string_literal: true

describe DocCategories::CategoryIndexManager do
  fab!(:category, :category_with_definition)
  fab!(:topic) { Fabricate(:topic_with_op, category: category) }
  fab!(:other_category, :category_with_definition)
  fab!(:other_topic) { Fabricate(:topic_with_op, category: other_category) }
  fab!(:private_message, :private_message_topic)

  subject(:manager) { described_class.new(category) }

  before { SiteSetting.doc_categories_enabled = true }

  describe "#assign!" do
    before { allow(Jobs).to receive(:enqueue) }

    it "persists a new index topic and enqueues a refresh" do
      result = manager.assign!(topic.id)

      expect(result).to eq(true)
      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index&.index_topic_id).to eq(topic.id)
      expect(Jobs).to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
    end

    it "rejects topics from other categories" do
      expect(manager.assign!(other_topic.id)).to eq(false)
      expect(Jobs).not_to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
      expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
    end

    it "rejects private messages" do
      expect(manager.assign!(private_message.id)).to eq(false)
      expect(Jobs).not_to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
      expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
    end

    it "rejects trashed topics" do
      trashed_topic = Fabricate(:topic_with_op, category: category)
      trashed_topic.trash!

      expect(manager.assign!(trashed_topic.id)).to eq(false)
      expect(Jobs).not_to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
      expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
    end

    it "rejects topic ids that cannot be resolved" do
      expect(manager.assign!("abc")).to eq(false)
      expect(manager.assign!(0)).to eq(false)
      expect(Jobs).not_to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
      expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
    end

    it "returns false when removing a missing index" do
      expect(manager.assign!(nil)).to eq(false)
      expect(Jobs).not_to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
    end

    it "resets an existing index when nil is provided" do
      manager.assign!(topic.id)
      expect(DocCategories::Index.exists?(category_id: category.id)).to eq(true)

      expect(manager.assign!(nil)).to eq(true)
      expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
      expect(Jobs).to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      ).twice
    end

    it "does not reassign when the index is unchanged" do
      Fabricate(:doc_categories_index, category: category, index_topic: topic)

      expect(manager.assign!(topic.id)).to eq(false)
      expect(Jobs).not_to have_received(:enqueue).with(
        :doc_categories_refresh_index,
        category_id: category.id,
      )
    end
  end
end
