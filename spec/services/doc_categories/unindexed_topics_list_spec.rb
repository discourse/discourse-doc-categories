# frozen_string_literal: true

RSpec.describe DocCategories::UnindexedTopicsList do
  describe described_class::Contract, type: :model do
    subject(:contract) { described_class.new }

    it { is_expected.to validate_presence_of(:category_id) }
    it { is_expected.to allow_values(0, 50, "0", "50").for(:limit) }
    it { is_expected.not_to allow_values(-1, 1, 1000, nil).for(:limit) }
    it { is_expected.to allow_values(0, "0", "999999").for(:page) }
    it { is_expected.not_to allow_values(-1, "invalid", "1000000", nil).for(:page) }
    it { is_expected.to allow_values(nil, [], [1, "2"]).for(:exclude_topic_ids) }
    it { is_expected.not_to allow_values("all", ["bad-id"], [0], [-1]).for(:exclude_topic_ids) }
    it { is_expected.to allow_values(nil, [], ["/t/example/1"]).for(:exclude_hrefs) }
    it { is_expected.not_to allow_values("all", [123], ["x" * 2001]).for(:exclude_hrefs) }
    it { is_expected.to allow_values(nil, "", "x" * 200).for(:search) }
    it { is_expected.not_to allow_value("x" * 201).for(:search) }

    it "limits the number of excluded topics and URLs" do
      stub_const(DocCategories::UnindexedTopicsList, :MAX_EXCLUDED_TOPICS, 1) do
        expect(contract).not_to allow_value([1, 2]).for(:exclude_topic_ids)
        expect(contract).not_to allow_value(%w[/a /b]).for(:exclude_hrefs)
      end
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:acting_user, :admin)
    fab!(:category, :category_with_definition)
    fab!(:topic) { Fabricate(:topic, category: category, title: "Alpha topic title here") }
    fab!(:other_topic) { Fabricate(:topic, category: category, title: "Beta topic title here") }

    let(:params) { { category_id: category.id } }
    let(:dependencies) { { guardian: acting_user.guardian } }

    before do
      SiteSetting.doc_categories_enabled = true
      SiteSetting.doc_categories_index_editor = true
    end

    context "when the contract is invalid" do
      let(:params) { { category_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context "when the category is missing" do
      let(:params) { { category_id: -1 } }

      it { is_expected.to fail_to_find_a_model(:category) }
    end

    context "when the actor is not an admin" do
      fab!(:acting_user, :user)

      it { is_expected.to fail_a_policy(:can_list_topics) }
    end

    context "when a category moderator requests a private category" do
      fab!(:acting_user, :moderator)
      fab!(:private_group, :group)
      fab!(:category) { Fabricate(:private_category, group: private_group) }

      it { is_expected.to fail_a_policy(:can_list_topics) }
    end

    context "when there is no signed-in actor" do
      let(:dependencies) { { guardian: Guardian.new } }

      it { is_expected.to fail_a_policy(:can_list_topics) }
    end

    context "when the plugin is disabled" do
      before { SiteSetting.doc_categories_enabled = false }

      it { is_expected.to fail_a_policy(:can_list_topics) }
    end

    context "when the editor is disabled without an existing direct index" do
      before { SiteSetting.doc_categories_index_editor = false }

      it { is_expected.to fail_a_policy(:can_list_topics) }
    end

    context "when the editor is disabled with an existing direct index" do
      fab!(:index) do
        Fabricate(
          :doc_categories_index,
          category: category,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      end

      before { SiteSetting.doc_categories_index_editor = false }

      it { is_expected.to run_successfully }
    end

    context "when topics are available" do
      it { is_expected.to run_successfully }

      it "lists candidates in title order without the category definition" do
        expect(result[:topics].map(&:id)).to eq([topic.id, other_topic.id])
        expect(result[:total_count]).to eq(2)
      end
    end

    context "when every candidate is already indexed" do
      let(:params) { { category_id: category.id, exclude_topic_ids: [topic.id, other_topic.id] } }

      it { is_expected.to run_successfully }

      it "returns an empty page and zero count" do
        expect(result[:topics]).to be_empty
        expect(result[:total_count]).to eq(0)
      end
    end

    context "when counting without loading a page" do
      let(:params) { { category_id: category.id, limit: 0 } }

      it "returns the count and an empty page" do
        expect(result).to run_successfully
        expect(result[:topics]).to be_empty
        expect(result[:total_count]).to eq(2)
      end
    end

    context "when the requested page is beyond the candidates" do
      let(:params) { { category_id: category.id, page: 1 } }

      it "returns an empty page without losing the total count" do
        expect(result).to run_successfully
        expect(result[:topics]).to be_empty
        expect(result[:total_count]).to eq(2)
      end
    end
  end
end
