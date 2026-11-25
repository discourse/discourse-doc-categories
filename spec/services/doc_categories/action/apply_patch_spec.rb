# frozen_string_literal: true

RSpec.describe DocCategories::Action::ApplyPatch do
  describe ".call" do
    subject(:apply_patch) { described_class.call(patch:) }

    fab!(:index) do
      Fabricate(:doc_categories_index, index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT)
    end
    fab!(:moving_section) { Fabricate(:doc_categories_sidebar_section, index:, position: 0) }
    fab!(:destination_section) { Fabricate(:doc_categories_sidebar_section, index:, position: 1) }
    fab!(:anchor_section) do
      Fabricate(
        :doc_categories_sidebar_section,
        index:,
        parent_section: destination_section,
        position: 0,
      )
    end
    fab!(:sibling_link) do
      Fabricate(
        :doc_categories_sidebar_link,
        sidebar_section: destination_section,
        href: "/sibling-link",
        position: 1,
      )
    end
    fab!(:moving_section_link) do
      Fabricate(
        :doc_categories_sidebar_link,
        sidebar_section: moving_section,
        href: "/moving-section-link",
        position: 0,
      )
    end

    let(:patch) do
      DocCategories::IndexPatcher::Patch.new(category: index.category, index:, params:).prepare!
    end
    let(:params) do
      DocCategories::IndexPatcher::Contract.new(
        category_id: index.category_id,
        operation:,
        section_id: moving_section.id,
        placement: "after",
        relative_section_id: anchor_section.id,
      )
    end
    let(:operation) { "move_section" }

    it "moves a section between a sibling section and link while preserving its own links" do
      apply_patch

      items = index.sidebar_structure(include_empty: true).first.fetch(:items)
      expect(items.map { |item| [item[:type], item[:id] || item[:href]] }).to eq(
        [
          ["section", anchor_section.id],
          ["section", moving_section.id],
          ["link", sibling_link.href],
        ],
      )
      expect(moving_section.sidebar_links.pluck(:id)).to eq([moving_section_link.id])
    end

    context "when the operation is unknown" do
      let(:operation) { "replace_index" }

      it "raises an argument error" do
        expect { apply_patch }.to raise_error(
          ArgumentError,
          "Unknown index patch operation: \"replace_index\"",
        )
      end
    end
  end
end
