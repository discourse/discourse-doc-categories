# frozen_string_literal: true

RSpec.describe DocCategories::AutoIndexer::AddTopic do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:topic_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

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
    let(:dependencies) { {} }
    let(:messages) { MessageBus.track_publish("/categories") { result } }

    before { SiteSetting.doc_categories_enabled = true }

    context "when the contract is invalid" do
      let(:params) { { topic_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context "when the topic does not exist" do
      let(:params) { { topic_id: -999 } }

      it { is_expected.to fail_to_find_a_model(:topic) }
    end

    context "when the topic is trashed" do
      before { topic.trash! }

      # Trashable default scope excludes trashed topics from find_by
      it { is_expected.to fail_to_find_a_model(:topic) }
    end

    context "when the topic is not visible" do
      before { topic.update!(visible: false) }

      it { is_expected.to fail_a_policy(:topic_qualifies) }
    end

    context "when the topic is a private message" do
      fab!(:pm, :private_message_topic)
      let(:params) { { topic_id: pm.id } }

      it { is_expected.to fail_a_policy(:topic_qualifies) }
    end

    context "when the topic is a banner" do
      before { topic.update!(archetype: Archetype.banner) }

      it { is_expected.to fail_a_policy(:topic_qualifies) }
    end

    context "when the topic is already linked by URL alone" do
      fab!(:link) do
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: auto_section,
          topic: nil,
          href: topic.relative_url,
          position: 0,
        )
      end

      it "leaves the category unpublished" do
        expect(messages).to be_empty
        expect(result).to run_successfully
        expect(auto_section.sidebar_links.pluck(:id)).to eq([link.id])
      end
    end

    context "when everything is valid" do
      it { is_expected.to run_successfully }

      it "creates an auto-indexed sidebar link" do
        expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(1)

        link = DocCategories::SidebarLink.auto_indexed.last
        expect(link.topic_id).to eq(topic.id)
        expect(link.sidebar_section).to eq(auto_section)
        expect(link.auto_indexed).to eq(true)
      end

      it "sets the correct position" do
        result
        link = DocCategories::SidebarLink.auto_indexed.last
        expect(link.position).to eq(0)
      end

      it "sets the next position after an existing automatic link" do
        other_topic = Fabricate(:topic, category: category)
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: auto_section,
          topic: other_topic,
          href: other_topic.relative_url,
          position: 0,
          auto_indexed: true,
        )
        result

        links = auto_section.sidebar_links.auto_indexed.order(:position)
        expect(links.pluck(:topic_id, :position)).to eq([[other_topic.id, 0], [topic.id, 1]])
      end

      it "skips indexes where the topic is already linked" do
        Fabricate(
          :doc_categories_sidebar_link,
          sidebar_section: auto_section,
          topic: topic,
          href: topic.relative_url,
          position: 0,
        )

        expect { result }.not_to change { DocCategories::SidebarLink.count }
      end

      it "skips indexes where the section is full" do
        stub_const(DocCategories::Index, :MAX_LINKS_PER_SECTION, 1) do
          Fabricate(
            :doc_categories_sidebar_link,
            sidebar_section: auto_section,
            href: "/t/existing/1",
            position: 0,
          )

          expect { result }.not_to change { DocCategories::SidebarLink.count }
        end
      end

      it "does not match indexes whose category does not match the topic" do
        other_category = Fabricate(:category_with_definition)
        other_index =
          Fabricate(
            :doc_categories_index,
            category: other_category,
            index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
          )
        Fabricate(
          :doc_categories_sidebar_section,
          index: other_index,
          auto_index: true,
          title: "Auto",
          position: 0,
        )

        # topic is in `category`, not `other_category`
        expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(1)
        expect(
          DocCategories::SidebarLink
            .auto_indexed
            .joins(:sidebar_section)
            .where(sidebar_section: { index_id: other_index.id })
            .count,
        ).to eq(0)
      end

      context "when subcategory indexing is enabled" do
        fab!(:subcategory) { Fabricate(:category, parent_category: category) }
        fab!(:sub_topic) { Fabricate(:topic, category: subcategory) }

        let(:params) { { topic_id: sub_topic.id } }

        before { index.update!(auto_index_include_subcategories: true) }

        it "includes topics from subcategories" do
          expect { result }.to change { DocCategories::SidebarLink.auto_indexed.count }.by(1)
        end
      end

      context "when subcategory indexing includes a private category" do
        fab!(:group)
        fab!(:subcategory) { Fabricate(:private_category, parent_category: category, group: group) }
        fab!(:sub_topic) { Fabricate(:topic, category: subcategory) }

        let(:params) { { topic_id: sub_topic.id } }

        before { index.update!(auto_index_include_subcategories: true) }

        it "leaves private subcategory topics unindexed" do
          expect(result).to run_successfully
          expect(auto_section.sidebar_links).to be_empty
        end
      end

      context "when the index belongs to a private category" do
        fab!(:group)

        before do
          category.set_permissions(group.name => :full)
          category.save!
        end

        it "indexes the category's own topics" do
          expect(result).to run_successfully
          expect(auto_section.sidebar_links.pluck(:topic_id)).to eq([topic.id])
        end
      end

      context "when subcategory indexing is disabled" do
        fab!(:subcategory) { Fabricate(:category, parent_category: category) }
        fab!(:sub_topic) { Fabricate(:topic, category: subcategory) }

        let(:params) { { topic_id: sub_topic.id } }

        it "leaves subcategory topics unindexed" do
          expect { result }.not_to change { DocCategories::SidebarLink.auto_indexed.count }
        end
      end
    end

    context "when an index is topic-managed" do
      fab!(:topic_mode_index, :doc_categories_index)
      fab!(:topic_section) do
        Fabricate(
          :doc_categories_sidebar_section,
          index: topic_mode_index,
          auto_index: true,
          title: "Auto",
          position: 0,
        )
      end
      fab!(:topic_in_that_category) { Fabricate(:topic, category: topic_mode_index.category) }

      let(:params) { { topic_id: topic_in_that_category.id } }

      it "leaves the topic-managed index untouched" do
        expect(result).to run_successfully
        expect(topic_section.sidebar_links).to be_empty
      end
    end
  end
end
