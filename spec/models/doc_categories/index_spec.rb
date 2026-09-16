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

  describe "#sidebar_structure" do
    fab!(:direct_index) do
      described_class.create!(
        category: category,
        index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
      )
    end

    it "returns a link with text from topic title and href from topic URL" do
      topic = Fabricate(:topic, category: category, title: "My awesome topic")
      section = direct_index.sidebar_sections.create!(position: 0, title: "Docs")
      section.sidebar_links.create!(position: 0, topic: topic, href: topic.relative_url)

      structure = direct_index.sidebar_structure
      link = structure.first[:links].first

      expect(link[:text]).to eq("My awesome topic")
      expect(link[:href]).to eq(topic.relative_url)
      expect(link[:topic_id]).to eq(topic.id)
    end

    it "filters out links whose topic has been trashed" do
      topic = Fabricate(:topic, category: category)
      section = direct_index.sidebar_sections.create!(position: 0, title: "Docs")
      section.sidebar_links.create!(position: 0, topic: topic, href: topic.relative_url)
      topic.trash!

      structure = direct_index.sidebar_structure

      expect(structure).to be_empty
    end

    it "marks a link with custom_title when the link has its own title" do
      topic = Fabricate(:topic, category: category, title: "Original topic title for testing")
      section = direct_index.sidebar_sections.create!(position: 0, title: "Docs")
      section.sidebar_links.create!(
        position: 0,
        title: "Custom name",
        topic: topic,
        href: topic.relative_url,
      )

      structure = direct_index.sidebar_structure
      link = structure.first[:links].first

      expect(link[:text]).to eq("Custom name")
      expect(link[:custom_title]).to eq(true)
      expect(link[:topic_title]).to eq("Original topic title for testing")
    end

    it "does not set custom_title when the link has no explicit title" do
      topic = Fabricate(:topic, category: category, title: "Original topic title for testing")
      section = direct_index.sidebar_sections.create!(position: 0, title: "Docs")
      section.sidebar_links.create!(position: 0, topic: topic, href: topic.relative_url)

      structure = direct_index.sidebar_structure
      link = structure.first[:links].first

      expect(link[:custom_title]).to eq(false)
    end

    it "includes auto_indexed flag on links that are auto-indexed" do
      topic = Fabricate(:topic, category: category)
      section =
        direct_index.sidebar_sections.create!(position: 0, title: "Topics", auto_index: true)
      section.sidebar_links.create!(
        position: 0,
        topic: topic,
        href: topic.relative_url,
        auto_indexed: true,
      )

      structure = direct_index.sidebar_structure
      link = structure.first[:links].first

      expect(link[:auto_indexed]).to eq(true)
    end

    it "does not include auto_indexed key for manually added links" do
      section = direct_index.sidebar_sections.create!(position: 0, title: "Docs")
      section.sidebar_links.create!(position: 0, title: "Manual", href: "/t/slug/1")

      structure = direct_index.sidebar_structure
      link = structure.first[:links].first

      expect(link).not_to have_key(:auto_indexed)
    end

    it "keeps an auto-index section even when it has no valid links" do
      section =
        direct_index.sidebar_sections.create!(position: 0, title: "Topics", auto_index: true)

      structure = direct_index.sidebar_structure

      expect(structure.length).to eq(1)
      expect(structure.first[:text]).to eq("Topics")
      expect(structure.first[:auto_index]).to eq(true)
      expect(structure.first[:links]).to be_empty
    end

    it "omits a non-auto-index section when all its links are invalid" do
      topic = Fabricate(:topic, category: category)
      section = direct_index.sidebar_sections.create!(position: 0, title: "Docs")
      section.sidebar_links.create!(position: 0, topic: topic, href: topic.relative_url)
      topic.trash!

      valid_section = direct_index.sidebar_sections.create!(position: 1, title: "Others")
      valid_section.sidebar_links.create!(
        position: 0,
        title: "External",
        href: "https://example.com",
      )

      structure = direct_index.sidebar_structure

      expect(structure.length).to eq(1)
      expect(structure.first[:text]).to eq("Others")
    end
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
