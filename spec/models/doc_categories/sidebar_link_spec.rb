# frozen_string_literal: true

describe DocCategories::SidebarLink do
  fab!(:category) { Fabricate(:category_with_definition) }
  fab!(:index_topic) do
    Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic:) }
  end

  fab!(:doc_index) { Fabricate(:doc_categories_index, category:, index_topic:) }
  fab!(:sidebar_section) do
    Fabricate(:doc_categories_sidebar_section, index: doc_index, position: 1, title: "Links")
  end

  it "enforces unique positioning within a section" do
    described_class.create!(sidebar_section:, position: 1, title: "Docs", href: "/docs")

    duplicate = described_class.new(sidebar_section:, position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:position]).to include("has already been taken")
  end

  it "requires a href" do
    link = described_class.new(sidebar_section:, position: 1, title: "Docs")

    expect(link).not_to be_valid
    expect(link.errors[:href]).to include("can't be blank")
  end

  it "accepts linking directly to a topic" do
    topic = Fabricate(:topic, category:)

    link = described_class.create!(sidebar_section:, position: 1, title: topic.title, topic:)

    expect(link.reload.topic).to eq(topic)
    expect(link.href).to eq(topic.relative_url)
  end

  it "rejects deleted topics" do
    topic = Fabricate(:topic, category: category).tap { |topic| Fabricate(:post, topic:) }
    topic.trash!

    link = described_class.new(sidebar_section:, position: 1, topic:)

    expect(link).not_to be_valid
    expect(link.errors[:topic_id]).to include("cannot reference a deleted topic")
  end

  it "rejects href values longer than the limit" do
    link = described_class.new(sidebar_section:, position: 1, href: "https://" + "a" * 1992)

    expect(link).to be_valid

    link.href = "https://" + "a" * 1993

    expect(link).not_to be_valid
    expect(link.errors[:href]).to include("is too long (maximum is 2000 characters)")
  end

  it "rejects title values longer than the limit" do
    link = described_class.new(sidebar_section:, position: 1, href: "/docs", title: "a" * 255)

    expect(link).to be_valid

    link.title = "a" * 256

    expect(link).not_to be_valid
    expect(link.errors[:title]).to include("is too long (maximum is 255 characters)")
  end
end
