# frozen_string_literal: true

RSpec.describe DocCategories::AutoIndexer::Sync do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:index_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

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
    let(:messages) { MessageBus.track_publish("/categories") { result } }

    let(:dependencies) { {} }

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

      it { is_expected.to fail_to_find_a_model(:auto_index_section) }
    end

    context "when there are no eligible topics or stale links" do
      it "leaves the category unpublished" do
        expect(messages).to be_empty
        expect(result).to run_successfully
      end
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

      context "when subcategory indexing is enabled" do
        fab!(:subcategory) { Fabricate(:category, parent_category: category) }
        fab!(:sub_topic) { Fabricate(:topic, category: subcategory) }

        before { index.update!(auto_index_include_subcategories: true) }

        it "includes topics from subcategories" do
          result
          expect(auto_section.sidebar_links.auto_indexed.pluck(:topic_id)).to include(sub_topic.id)
        end
      end

      context "when subcategory indexing is disabled" do
        fab!(:subcategory) { Fabricate(:category, parent_category: category) }
        fab!(:sub_topic) { Fabricate(:topic, category: subcategory) }

        it "leaves subcategory topics unindexed" do
          result
          expect(auto_section.sidebar_links.auto_indexed.pluck(:topic_id)).not_to include(
            sub_topic.id,
          )
        end
      end

      context "when a full section contains a stale link" do
        fab!(:stale_topic) { Fabricate(:topic, category: category) }
        fab!(:stale_link) do
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: auto_section,
            topic: stale_topic,
            href: stale_topic.relative_url,
            position: 0,
            auto_indexed: true,
          )
        end

        before { stale_topic.trash! }

        it "reclaims capacity before adding a qualifying topic" do
          stale_link_id = stale_link.id
          stub_const(DocCategories::Index, :MAX_LINKS_PER_SECTION, 1) do
            expect(result).to run_successfully
            expect(DocCategories::SidebarLink.exists?(id: stale_link_id)).to eq(false)
            expect(auto_section.sidebar_links.auto_indexed.count).to eq(1)
            expect(auto_section.sidebar_links.auto_indexed.first.topic_id).to be_in(
              [topic_1.id, topic_2.id],
            )
          end
        end
      end

      context "when the section is full with valid links" do
        fab!(:existing_link) do
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: auto_section,
            topic: topic_1,
            href: topic_1.relative_url,
            position: 0,
            auto_indexed: true,
          )
        end

        it "leaves the category unpublished when candidates cannot be added" do
          stub_const(DocCategories::Index, :MAX_LINKS_PER_SECTION, 1) do
            expect(messages).to be_empty
            expect(result).to run_successfully
          end
        end
      end

      context "with section capacity limits" do
        it "respects the max links per section limit" do
          stub_const(DocCategories::Index, :MAX_LINKS_PER_SECTION, 1) do
            result
            expect(auto_section.sidebar_links.auto_indexed.count).to eq(1)
          end
        end
      end
    end
  end
end
