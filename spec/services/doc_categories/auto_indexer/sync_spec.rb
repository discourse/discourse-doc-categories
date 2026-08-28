# frozen_string_literal: true

RSpec.describe DocCategories::AutoIndexer::Sync do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:index_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:) }

    fab!(:category)
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

    let(:params) { { index_id: index.id } }

    before { SiteSetting.doc_categories_enabled = true }

    context "when the contract is invalid" do
      let(:params) { { index_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context "when the index does not exist" do
      let(:params) { { index_id: -999 } }

      it { is_expected.to fail_to_find_a_model(:index) }
    end

    context "when the index has no auto-index section" do
      before { auto_section.update!(auto_index: false) }

      it { is_expected.to fail_a_policy(:has_auto_index_section) }
    end

    context "when the index has an auto-index section" do
      fab!(:topic_1) { Fabricate(:topic, category: category) }
      fab!(:topic_2) { Fabricate(:topic, category: category) }

      it { is_expected.to run_successfully }

      it "creates links for qualifying topics" do
        expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(2)

        linked_topic_ids = auto_section.sidebar_links.auto_indexed.pluck(:topic_id)
        expect(linked_topic_ids).to contain_exactly(topic_1.id, topic_2.id)
      end

      it "does not duplicate already-linked topics" do
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: auto_section,
          topic: topic_1,
          href: topic_1.relative_url,
          position: 0,
        )

        expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(1)

        expect(auto_section.sidebar_links.auto_indexed.pluck(:topic_id)).to contain_exactly(
          topic_2.id,
        )
      end

      it "excludes invisible topics" do
        topic_1.update!(visible: false)

        result
        linked_topic_ids = auto_section.sidebar_links.auto_indexed.pluck(:topic_id)
        expect(linked_topic_ids).to contain_exactly(topic_2.id)
      end

      it "excludes trashed topics" do
        topic_1.trash!

        result
        linked_topic_ids = auto_section.sidebar_links.auto_indexed.pluck(:topic_id)
        expect(linked_topic_ids).to contain_exactly(topic_2.id)
      end

      it "excludes private messages" do
        # PMs have a different archetype, so they won't match
        result
        pm = Fabricate(:private_message_topic)
        linked_topic_ids = auto_section.sidebar_links.auto_indexed.pluck(:topic_id)
        expect(linked_topic_ids).not_to include(pm.id)
      end

      it "removes stale auto-indexed links for topics no longer qualifying" do
        stale_link =
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: auto_section,
            topic: topic_1,
            href: topic_1.relative_url,
            position: 0,
            auto_indexed: true,
          )
        topic_1.trash!

        result
        expect(DocCategories::SidebarLink.exists?(id: stale_link.id)).to eq(false)
      end

      it "does not remove manually-created links even if the topic no longer qualifies" do
        manual_link =
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: auto_section,
            topic: topic_1,
            href: topic_1.relative_url,
            position: 0,
            auto_indexed: false,
          )
        topic_1.trash!

        result
        expect(DocCategories::SidebarLink.exists?(id: manual_link.id)).to eq(true)
      end

      context "with subcategories" do
        fab!(:subcategory) { Fabricate(:category, parent_category: category) }
        fab!(:sub_topic) { Fabricate(:topic, category: subcategory) }

        context "when auto_index_include_subcategories is true" do
          before { index.update!(auto_index_include_subcategories: true) }

          it "includes topics from subcategories" do
            result
            linked_topic_ids = auto_section.sidebar_links.auto_indexed.pluck(:topic_id)
            expect(linked_topic_ids).to include(sub_topic.id)
          end
        end

        context "when auto_index_include_subcategories is false" do
          it "does not include topics from subcategories" do
            result
            linked_topic_ids = auto_section.sidebar_links.auto_indexed.pluck(:topic_id)
            expect(linked_topic_ids).not_to include(sub_topic.id)
          end
        end
      end

      context "with section capacity limits" do
        it "respects the max links per section limit" do
          stub_const(described_class, "MAX_LINKS_PER_SECTION", 1) do
            result
            expect(auto_section.sidebar_links.auto_indexed.count).to eq(1)
          end
        end
      end
    end
  end
end
