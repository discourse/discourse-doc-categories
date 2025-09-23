# frozen_string_literal: true

describe DocCategories::SidebarLink do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:index_topic) do
    Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic: topic) }
  end

  let!(:doc_index) { DocCategories::Index.create!(category: category, index_topic: index_topic) }
  let!(:section) { DocCategories::SidebarSection.create!(index: doc_index, position: 1, title: "Links") }

  it "enforces unique positioning within a section" do
    described_class.create!(sidebar_section: section, position: 1, title: "Docs", href: "/docs")

    duplicate = described_class.new(sidebar_section: section, position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:position]).to include("has already been taken")
  end

  it "requires a topic or href" do
    link = described_class.new(sidebar_section: section, position: 1, title: "Docs")

    expect(link).not_to be_valid
    expect(link.errors[:base]).to include("must include either a topic or href")
  end

  it "accepts linking directly to a topic" do
    linked_topic = Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic: topic) }

    link =
      described_class.create!(
        sidebar_section: section,
        position: 1,
        title: linked_topic.title,
        topic: linked_topic,
      )

    expect(link.reload.topic).to eq(linked_topic)
    expect(link.href).to be_nil
  end

  it "rejects deleted topics" do
    linked_topic = Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic: topic) }
    linked_topic.trash!

    link =
      described_class.new(
        sidebar_section: section,
        position: 1,
        topic: linked_topic,
      )

    expect(link).not_to be_valid
    expect(link.errors[:topic_id]).to include("cannot reference a deleted topic")
  end

  it "rejects href values longer than the limit" do
    link =
      described_class.new(
        sidebar_section: section,
        position: 1,
        href: "https://" + "a" * 1992,
      )

    expect(link).to be_valid

    link.href = "https://" + "a" * 1993

    expect(link).not_to be_valid
    expect(link.errors[:href]).to include("is too long (maximum is 2000 characters)")
  end
end
