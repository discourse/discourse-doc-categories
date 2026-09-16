# frozen_string_literal: true

RSpec.describe DocCategories::AutoIndexer::RemoveTopic do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:topic_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:) }

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

    let(:params) { { topic_id: topic.id } }

    before { SiteSetting.doc_categories_enabled = true }

    context "when the contract is invalid" do
      let(:params) { { topic_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context "when there are no auto-indexed links for the topic" do
      it { is_expected.to run_successfully }

      it "does not destroy any links" do
        expect { result }.not_to change { DocCategories::SidebarLink.count }
      end
    end

    context "when auto-indexed links exist for the topic" do
      fab!(:auto_link) do
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: auto_section,
          topic: topic,
          href: topic.relative_url,
          position: 0,
          auto_indexed: true,
        )
      end

      it { is_expected.to run_successfully }

      it "destroys the auto-indexed links" do
        auto_link_id = auto_link.id
        expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(-1)
        expect(DocCategories::SidebarLink.find_by(id: auto_link_id)).to be_nil
      end

      it "does not destroy manually-created links for the same topic" do
        manual_link =
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: auto_section,
            topic: topic,
            href: topic.relative_url,
            position: 1,
            auto_indexed: false,
          )

        result
        expect(DocCategories::SidebarLink.exists?(id: manual_link.id)).to eq(true)
      end
    end

    context "when auto-indexed links exist across multiple indexes" do
      fab!(:other_category, :category_with_definition)
      fab!(:other_index) do
        Fabricate(
          :doc_categories_index,
          category: other_category,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      end
      fab!(:other_section) do
        Fabricate(
          :doc_categories_sidebar_section,
          index: other_index,
          auto_index: true,
          title: "Auto",
          position: 0,
        )
      end

      before do
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: auto_section,
          topic: topic,
          href: topic.relative_url,
          position: 0,
          auto_indexed: true,
        )
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: other_section,
          topic: topic,
          href: topic.relative_url,
          position: 0,
          auto_indexed: true,
        )
      end

      it "removes auto-indexed links from all indexes" do
        expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(-2)
      end
    end
  end
end
