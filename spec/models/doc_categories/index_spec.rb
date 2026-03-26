# frozen_string_literal: true

describe DocCategories::Index do
  fab!(:category, :category_with_definition)
  fab!(:index_topic) do
    Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic: topic) }
  end
  fab!(:alternate_topic) do
    Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic: topic) }
  end

  subject(:doc_index) { described_class.create!(category: category, index_topic: index_topic) }

  it "requires the index topic to match the category" do
    mismatched_category = Fabricate(:category_with_definition)
    mismatched_topic =
      Fabricate(:topic, category: mismatched_category).tap do |topic|
        Fabricate(:post, topic: topic)
      end

    record = described_class.new(category: category, index_topic: mismatched_topic)

    expect(record).not_to be_valid
    expect(record.errors[:index_topic_id]).to include("must belong to the same category")
  end

  it "enforces a unique category" do
    doc_index

    duplicate = described_class.new(category:, index_topic: alternate_topic)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:category_id]).to include("has already been taken")
  end

  it "enforces a unique index topic" do
    doc_index

    other_category = Fabricate(:category_with_definition)

    duplicate = described_class.new(category: other_category, index_topic: index_topic)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:index_topic_id]).to include("has already been taken")
  end

  it "allows multiple indexes with INDEX_TOPIC_ID_DIRECT (-1)" do
    cat1 = Fabricate(:category_with_definition)
    cat2 = Fabricate(:category_with_definition)

    index1 =
      described_class.create!(
        category: cat1,
        index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
      )
    index2 =
      described_class.new(
        category: cat2,
        index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
      )

    expect(index2).to be_valid
    expect { index2.save! }.not_to raise_error
  end

  it "skips index_topic_matches_category validation for direct mode" do
    record =
      described_class.new(
        category: category,
        index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
      )

    expect(record).to be_valid
  end

  describe "mode helpers" do
    it "returns mode_none? when index_topic_id is nil" do
      record = described_class.new(category: category, index_topic_id: nil)
      expect(record.mode_none?).to eq(true)
      expect(record.mode_direct?).to eq(false)
      expect(record.mode_topic?).to eq(false)
    end

    it "returns mode_direct? when index_topic_id is -1" do
      record =
        described_class.new(
          category: category,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      expect(record.mode_none?).to eq(false)
      expect(record.mode_direct?).to eq(true)
      expect(record.mode_topic?).to eq(false)
    end

    it "returns mode_topic? when index_topic_id is a positive integer" do
      record = described_class.new(category: category, index_topic: index_topic)
      expect(record.mode_none?).to eq(false)
      expect(record.mode_direct?).to eq(false)
      expect(record.mode_topic?).to eq(true)
    end
  end

  it "orders sidebar sections by their position" do
    later = doc_index.sidebar_sections.create!(position: 2, title: "Later")
    earlier = doc_index.sidebar_sections.create!(position: 1, title: "Earlier")

    expect(doc_index.reload.sidebar_sections.map(&:id)).to eq([earlier.id, later.id])
  end

  it "destroys associated sidebar sections and links when destroyed" do
    link = Fabricate(:doc_categories_sidebar_link)
    section = link.sidebar_section
    index = link.sidebar_section.index

    index.destroy
    expect(section).to be_destroyed
    expect(link).to be_destroyed
  end
end
