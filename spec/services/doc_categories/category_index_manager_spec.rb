# frozen_string_literal: true

RSpec.describe DocCategories::CategoryIndexManager do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:category_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:) }

    fab!(:category, :category_with_definition)
    fab!(:topic) { Fabricate(:topic_with_op, category: category) }
    fab!(:other_category, :category_with_definition)
    fab!(:other_topic) { Fabricate(:topic_with_op, category: other_category) }
    fab!(:private_message, :private_message_topic)

    let(:params) { { category_id: category.id, topic_id: topic.id } }

    before do
      SiteSetting.doc_categories_enabled = true
      allow(Jobs).to receive(:enqueue)
    end

    context "when assigning a topic" do
      it { is_expected.to run_successfully }

      it "persists a new index topic and enqueues a refresh" do
        result

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index&.index_topic_id).to eq(topic.id)
        expect(Jobs).to have_received(:enqueue).with(
          :doc_categories_refresh_index,
          category_id: category.id,
        )
      end
    end

    context "when the topic is from another category" do
      let(:params) { { category_id: category.id, topic_id: other_topic.id } }

      it { is_expected.to fail_a_policy(:valid_index_topic) }

      it "does not create an index" do
        result
        expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
      end
    end

    context "when the topic is a private message" do
      let(:params) { { category_id: category.id, topic_id: private_message.id } }

      it { is_expected.to fail_a_policy(:valid_index_topic) }
    end

    context "when the topic is trashed" do
      before { topic.trash! }

      it { is_expected.to fail_to_find_a_model(:topic) }
    end

    context "when the topic_id is unresolvable" do
      let(:params) { { category_id: category.id, topic_id: "abc" } }

      it "treats it as a remove action" do
        result
        expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
      end
    end

    context "when removing an index" do
      let(:params) { { category_id: category.id, topic_id: nil } }

      context "when no index exists" do
        it { is_expected.to run_successfully }
      end

      context "when an index exists" do
        before { described_class.call(params: { category_id: category.id, topic_id: topic.id }) }

        it { is_expected.to run_successfully }

        it "destroys the index" do
          expect(DocCategories::Index.exists?(category_id: category.id)).to eq(true)
          result
          expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
        end
      end

      it "destroys the index even if sidebar sections exist" do
        described_class.call(params: { category_id: category.id, topic_id: topic.id })
        index = DocCategories::Index.find_by(category_id: category.id)
        index.sidebar_sections.create!(title: "Test Section", position: 0)

        result
        expect(DocCategories::Index.exists?(category_id: category.id)).to eq(false)
      end
    end

    context "when assigning direct mode" do
      let(:params) { { category_id: category.id, topic_id: -1 } }

      it { is_expected.to run_successfully }

      it "creates a direct-mode index" do
        result
        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index).to be_present
        expect(index.mode_direct?).to eq(true)
        expect(index.index_topic_id).to eq(DocCategories::Index::INDEX_TOPIC_ID_DIRECT)
      end

      it "is a no-op when already in direct mode" do
        described_class.call(params: { category_id: category.id, topic_id: -1 })
        described_class.call(params: { category_id: category.id, topic_id: -1 })

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.mode_direct?).to eq(true)
      end

      it "switches from topic mode to direct mode" do
        described_class.call(params: { category_id: category.id, topic_id: topic.id })
        described_class.call(params: { category_id: category.id, topic_id: -1 })

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.mode_direct?).to eq(true)
      end

      it "clears direct-mode sidebar sections when switching to topic mode" do
        described_class.call(params: { category_id: category.id, topic_id: -1 })
        index = DocCategories::Index.find_by(category_id: category.id)
        index.sidebar_sections.create!(title: "Editor Section", position: 0)
        expect(index.sidebar_sections.count).to eq(1)

        described_class.call(params: { category_id: category.id, topic_id: topic.id })

        index.reload
        expect(index.mode_topic?).to eq(true)
        expect(index.sidebar_sections.count).to eq(0)
      end
    end

    context "when the index is already assigned to the same topic" do
      before { Fabricate(:doc_categories_index, category: category, index_topic: topic) }

      it { is_expected.to run_successfully }

      it "does not enqueue a refresh" do
        result
        expect(Jobs).not_to have_received(:enqueue).with(
          :doc_categories_refresh_index,
          category_id: category.id,
        )
      end
    end
  end
end
