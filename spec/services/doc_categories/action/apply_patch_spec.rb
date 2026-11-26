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
      DocCategories::IndexPatcher::Patch.new(category:, index: patch_index, params:).prepare!
    end
    let(:category) { index.category }
    let(:patch_index) { index }
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

    it "moves a section around a position-only update to an existing trashed-topic link" do
      trashed_topic = Fabricate(:topic)
      sibling_link.update!(topic: trashed_topic)
      trashed_topic.trash!

      apply_patch

      items = index.sidebar_structure(include_empty: true).first.fetch(:items)
      expect(items.pluck(:id)).to eq([anchor_section.id, moving_section.id])
      expect(sibling_link.reload.position).to eq(moving_section.reload.position + 1)
      expect(moving_section.sidebar_links.pluck(:id)).to eq([moving_section_link.id])
    end

    context "when adding a section to a category without an index" do
      fab!(:new_category, :category_with_definition)
      fab!(:topic) { Fabricate(:topic, category: new_category) }

      let(:category) { new_category }
      let(:patch_index) { nil }
      let(:params) do
        DocCategories::IndexPatcher::Contract.new(
          category_id: category.id,
          operation: "add_section",
          title: "Setup",
          topic_ids: [topic.id],
        )
      end

      it "creates a direct index and a section with the initial topic links" do
        apply_patch

        persisted_index = category.reload.doc_categories_index
        expect(persisted_index).to be_mode_direct
        section = persisted_index.sidebar_sections.find_by!(title: "Setup")
        expect(section.sidebar_links.pluck(:topic_id, :position)).to eq([[topic.id, 0]])
      end
    end

    context "when appending topic links" do
      fab!(:topic) { Fabricate(:topic, category: index.category) }
      fab!(:other_topic) { Fabricate(:topic, category: index.category) }

      let(:params) do
        DocCategories::IndexPatcher::Contract.new(
          category_id: category.id,
          operation: "add_topic_links",
          section_id: destination_section.id,
          topic_ids: [other_topic.id, topic.id],
        )
      end

      it "appends the links after the existing entries in request order" do
        apply_patch

        expect(
          destination_section.sidebar_links.order(:position).pluck(:topic_id, :position),
        ).to eq([[nil, 1], [other_topic.id, 2], [topic.id, 3]])
      end
    end

    context "when removing a section with descendants" do
      let(:params) do
        DocCategories::IndexPatcher::Contract.new(
          category_id: category.id,
          operation: "remove_section",
          section_id: destination_section.id,
        )
      end

      it "removes the section, its descendants, and their links" do
        link_id = sibling_link.id

        apply_patch

        expect(index.reload.sidebar_sections.pluck(:id)).to eq([moving_section.id])
        expect(DocCategories::SidebarLink.exists?(link_id)).to eq(false)
      end
    end

    context "when removing a URL-only link" do
      fab!(:topic) { Fabricate(:topic, category: index.category) }

      let(:params) do
        DocCategories::IndexPatcher::Contract.new(
          category_id: category.id,
          operation: "remove_topic_link",
          section_id: destination_section.id,
          topic_id: topic.id,
        )
      end

      before { sibling_link.update!(href: topic.relative_url) }

      it "removes the saved link without removing the topic" do
        apply_patch

        expect(destination_section.sidebar_links).to be_empty
        expect(Topic.exists?(topic.id)).to eq(true)
      end
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
