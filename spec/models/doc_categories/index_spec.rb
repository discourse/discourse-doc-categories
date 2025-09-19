# frozen_string_literal: true

describe DocCategories::Index do
  fab!(:category) { Fabricate(:category_with_definition) }
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
      Fabricate(:topic, category: mismatched_category).tap { |topic| Fabricate(:post, topic: topic) }

    record = described_class.new(category: category, index_topic: mismatched_topic)

    expect(record).not_to be_valid
    expect(record.errors[:index_topic_id]).to include("must belong to the same category")
  end

  it "enforces a unique category" do
    doc_index

    duplicate = described_class.new(category: category, index_topic: alternate_topic)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:category_id]).to be_present
  end

  it "enforces a unique index topic" do
    doc_index

    other_category = Fabricate(:category_with_definition)

    duplicate = described_class.new(category: other_category, index_topic: index_topic)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:index_topic_id]).to be_present
  end

  it "orders sidebar sections by their position" do
    later = doc_index.sidebar_sections.create!(position: 2, title: "Later")
    earlier = doc_index.sidebar_sections.create!(position: 1, title: "Earlier")

    expect(doc_index.reload.sidebar_sections.map(&:id)).to eq([earlier.id, later.id])
  end
end
