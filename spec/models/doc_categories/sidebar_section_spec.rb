# frozen_string_literal: true

describe DocCategories::SidebarSection do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:index_topic) do
    Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic: topic) }
  end

  fab!(:doc_index) do
    Fabricate(:doc_categories_index, category: category, index_topic: index_topic)
  end

  it "enforces unique positioning within an index" do
    described_class.create!(index: doc_index, position: 1, title: "General")

    duplicate = described_class.new(index: doc_index, position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:position]).to include("has already been taken")
  end

  it "allows the same position on different indexes" do
    described_class.create!(index: doc_index, position: 1, title: "General")

    other_category = Fabricate(:category_with_definition)
    other_topic =
      Fabricate(:topic, category: other_category).tap { |topic| Fabricate(:post, topic: topic) }
    other_index =
      Fabricate(:doc_categories_index, category: other_category, index_topic: other_topic)

    duplicate_position = described_class.new(index: other_index, position: 1)

    expect(duplicate_position).to be_valid
  end

  it "orders sidebar links by their position" do
    section = described_class.create!(index: doc_index, position: 1, title: "Links")

    later = section.sidebar_links.create!(position: 3, title: "Later", href: "/later")
    earlier = section.sidebar_links.create!(position: 1, title: "Earlier", href: "/earlier")
    middle = section.sidebar_links.create!(position: 2, title: "Middle", href: "/middle")

    expect(section.reload.sidebar_links.map(&:id)).to eq([earlier.id, middle.id, later.id])
  end

  it "cleans up sidebar links when destroyed" do
    section = described_class.create!(index: doc_index, position: 1, title: "Links")
    link = section.sidebar_links.create!(position: 1, title: "Earlier", href: "/earlier")

    section.destroy!

    expect { link.reload }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
