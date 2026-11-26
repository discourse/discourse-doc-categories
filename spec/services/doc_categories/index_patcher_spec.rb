# frozen_string_literal: true

RSpec.describe DocCategories::IndexPatcher do
  describe described_class::Contract, type: :model do
    it { is_expected.not_to allow_values(nil, 0, -1).for(:category_id) }
    it { is_expected.not_to allow_value("replace_index").for(:operation) }

    context "when adding a section" do
      subject(:contract) { described_class.new(category_id: 1, operation: "add_section") }

      it { is_expected.to validate_presence_of(:title) }

      it do
        is_expected.to validate_length_of(:title).is_at_most(
          DocCategories::SidebarSection::MAX_TITLE_LENGTH,
        )
      end

      it { is_expected.not_to allow_values([1, 1], [0], ["1"], 1).for(:topic_ids) }
      it { is_expected.not_to allow_value("near").for(:placement) }

      it "requires placement and its reference together" do
        contract.title = "Setup"
        contract.placement = "inside"
        expect(contract).to be_invalid
        expect(contract.errors[:relative_section_id]).to be_present

        contract.relative_section_id = 2
        expect(contract).to be_valid

        contract.placement = nil
        expect(contract).to be_invalid
        expect(contract.errors[:placement]).to be_present
      end
    end

    context "when moving a section" do
      subject(:contract) { described_class.new(category_id: 1, operation: "move_section") }

      it { is_expected.to validate_presence_of(:section_id) }
      it { is_expected.to validate_presence_of(:placement) }
      it { is_expected.to validate_presence_of(:relative_section_id) }
    end

    context "when removing a section" do
      subject(:contract) do
        described_class.new(category_id: 1, operation: "remove_section", section_id: 2, topic_id: 3)
      end

      it "rejects fields belonging to another operation" do
        expect(contract).to be_invalid
        expect(contract.errors.attribute_names).to contain_exactly(:topic_id)
      end
    end

    context "when adding topic links" do
      subject(:contract) do
        described_class.new(category_id: 1, operation: "add_topic_links", section_id: 2)
      end

      it { is_expected.to validate_presence_of(:topic_ids) }
    end

    context "when removing a topic link" do
      subject(:contract) do
        described_class.new(category_id: 1, operation: "remove_topic_link", section_id: 2)
      end

      it { is_expected.to validate_presence_of(:topic_id) }
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:acting_user, :admin)
    fab!(:category, :category_with_definition)

    let(:params) { { category_id:, operation: "add_section", title: "Testing" } }
    let(:category_id) { category.id }
    let(:dependencies) { { guardian: acting_user.guardian } }
    let(:messages) { MessageBus.track_publish("/categories") { result } }

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

    context "when the category is hidden from the admin" do
      fab!(:restricted_group, :group)
      fab!(:category) { Fabricate(:private_category, group: restricted_group) }

      before { SiteSetting.suppress_secured_categories_from_admin = true }

      it { is_expected.to fail_to_find_a_model(:category) }
    end

    context "when the index editor is disabled without a direct index" do
      before { SiteSetting.doc_categories_index_editor = false }

      it { is_expected.to fail_a_policy(:index_editor_enabled) }
    end

    context "when the plugin is disabled even with a direct index" do
      fab!(:index) do
        Fabricate(
          :doc_categories_index,
          category:,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      end

      before { SiteSetting.doc_categories_enabled = false }

      it { is_expected.to fail_a_policy(:index_editor_enabled) }
    end

    context "when the index editor is disabled with a direct index" do
      fab!(:index) do
        Fabricate(
          :doc_categories_index,
          category:,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      end

      before { SiteSetting.doc_categories_index_editor = false }

      it "allows updating the existing index" do
        expect(result).to run_successfully
        expect(index.sidebar_sections.pluck(:title)).to eq(["Testing"])
      end
    end

    context "when the index is topic-managed" do
      fab!(:index) { Fabricate(:doc_categories_index, category:) }

      it { is_expected.to fail_a_policy(:not_topic_managed) }
    end

    context "when the patch references a missing section" do
      let(:params) { { category_id:, operation: "remove_section", section_id: 2_147_483_647 } }

      it { is_expected.to fail_a_step(:prepare_patch) }
    end

    context "when every requested topic already has a URL-only link" do
      fab!(:index) do
        Fabricate(
          :doc_categories_index,
          category:,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      end
      fab!(:section) { Fabricate(:doc_categories_sidebar_section, index:) }
      fab!(:topic) { Fabricate(:topic, category:) }
      fab!(:link) do
        Fabricate(:doc_categories_sidebar_link, sidebar_section: section, href: topic.relative_url)
      end

      let(:params) do
        {
          category_id:,
          operation: "add_topic_links",
          section_id: section.id,
          topic_ids: [topic.id],
        }
      end

      it "succeeds without adding links or publishing the sidebar" do
        expect(messages).to be_empty
        expect(result).to run_successfully
        expect(section.sidebar_links.pluck(:id)).to eq([link.id])
      end
    end

    context "when creating the first section" do
      it "persists the new section and publishes the category" do
        expect(messages.flat_map { |message| message.data[:categories].pluck(:id) }).to eq(
          [category.id],
        )
        expect(result).to run_successfully
        index = category.reload.doc_categories_index
        expect(index).to be_mode_direct
        expect(index.sidebar_sections.pluck(:title)).to eq(["Testing"])
      end
    end

    context "when the enclosing transaction rolls back" do
      let(:messages) do
        MessageBus.track_publish("/categories") do
          Category.transaction(requires_new: true) do
            expect(result).to run_successfully
            expect(DocCategories::Index.exists?(category:)).to eq(true)
            raise ActiveRecord::Rollback
          end
        end
      end

      it "keeps the sidebar unpublished and discards the index" do
        expect(messages).to be_empty
        expect(DocCategories::Index.exists?(category:)).to eq(false)
      end
    end
  end

  describe ".call with independent database connections" do
    self.use_transactional_tests = false

    subject(:result) { described_class.call(params:, **dependencies) }

    let!(:category) do
      Fabricate(:category, user: Discourse.system_user, name: "Lock spec #{SecureRandom.hex(5)}")
    end

    let(:params) { { category_id: category.id, operation: "add_section", title: "Patched" } }
    let(:dependencies) { { guardian: Discourse.system_user.guardian } }

    before do
      SiteSetting.doc_categories_enabled = true
      SiteSetting.doc_categories_index_editor = true
    end

    after { category.destroy! }

    it "holds the same category lock as editor saves until the enclosing transaction commits" do
      pool = Category.connection_pool
      observer = pool.checkout(2)
      probe = "SELECT id FROM categories WHERE id = #{category.id} FOR UPDATE NOWAIT"

      Category.transaction do
        editor_result =
          DocCategories::IndexSaver.call(
            params: {
              category_id: category.id,
              sections: [
                { title: "Editor", links: [{ title: "Guide", href: "https://example.com" }] },
              ],
            },
            **dependencies,
          )
        expect(editor_result).to run_successfully
        expect { observer.execute(probe) }.to raise_error(ActiveRecord::LockWaitTimeout)
      end
      expect(observer.select_value(probe)).to eq(category.id)

      Category.transaction do
        expect(result).to run_successfully
        expect { observer.execute(probe) }.to raise_error(ActiveRecord::LockWaitTimeout)
      end
      expect(observer.select_value(probe)).to eq(category.id)
      expect(category.reload.doc_categories_index.sidebar_sections.pluck(:title)).to eq(
        %w[Editor Patched],
      )
    ensure
      pool.checkin(observer) if observer
    end
  end
end
