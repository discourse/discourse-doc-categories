# frozen_string_literal: true

RSpec.describe DocCategories::IndexPatcher do
  describe described_class::Contract, type: :model do
    it { is_expected.not_to allow_values(nil, 0, -1).for(:category_id) }
    it { is_expected.not_to allow_value("replace_index").for(:operation) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:acting_user, :admin)
    fab!(:category, :category_with_definition)

    let(:params) { { category_id:, operation: "add_section", title: "Testing" } }
    let(:category_id) { category.id }
    let(:dependencies) { { guardian: acting_user.guardian } }

    before do
      SiteSetting.doc_categories_enabled = true
      SiteSetting.doc_categories_index_editor = true
    end

    context "when the contract is invalid" do
      let(:category_id) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when the actor cannot edit indexes" do
      fab!(:acting_user, :user)

      it { is_expected.to fail_a_policy(:can_edit_index) }
    end

    context "when the category cannot be found" do
      let(:category_id) { 2_147_483_647 }

      it { is_expected.to fail_to_find_a_model(:category) }
    end

    context "when the index is topic-managed" do
      fab!(:index) { Fabricate(:doc_categories_index, category:) }

      it { is_expected.to fail_a_policy(:not_topic_managed) }
    end

    context "when the patch references a missing section" do
      let(:params) { { category_id:, operation: "remove_section", section_id: 2_147_483_647 } }

      it { is_expected.to fail_a_step(:apply_patch) }
    end

    context "when creating the first section" do
      it "creates a direct index and persists the new section" do
        expect(result).to run_successfully
        index = category.reload.doc_categories_index
        expect(index).to be_mode_direct
        expect(index.sidebar_sections.pluck(:title)).to eq(["Testing"])
      end
    end
  end
end
