# frozen_string_literal: true

require "rails_helper"

RSpec.describe DocCategories::IndexStructureRefresher do
  fab!(:documentation_category) { Fabricate(:category_with_definition) }
  fab!(:other_category) { Fabricate(:category_with_definition) }
  fab!(:doc_topic) do
    Fabricate(:topic_with_op, category: documentation_category)
  end
  fab!(:doc_topic_two) do
    Fabricate(:topic_with_op, category: documentation_category)
  end
  fab!(:other_category_topic) do
    Fabricate(:topic_with_op, category: other_category)
  end
  fab!(:invisible_topic) do
    Fabricate(:topic_with_op, category: documentation_category, visible: false)
  end
  fab!(:index_topic) do
    Fabricate(:topic_with_op, category: documentation_category).tap do |topic|
      topic.first_post.update!(
        raw: <<~MD,
          ## Docs Section
          * [#{doc_topic.title}](/t/#{doc_topic.slug}/#{doc_topic.id})
          * #{doc_topic_two.slug}: [#{doc_topic_two.title}](/t/#{doc_topic_two.slug}/#{doc_topic_two.id})
          * [#{other_category_topic.title}](/t/#{other_category_topic.slug}/#{other_category_topic.id})
          * [#{invisible_topic.title}](/t/#{invisible_topic.slug}/#{invisible_topic.id})
          * [External](https://example.com/docs)
          * No link here
        MD
      )
    end
  end

  before do
    Jobs.run_immediately!
    SiteSetting.doc_categories_enabled = true

    DocCategories::CategoryIndexManager.new(documentation_category).assign!(index_topic.id)
  end

  def sidebar_links
    DocCategories::SidebarLink
      .joins(sidebar_section: :index)
      .where(doc_categories_indexes: { category_id: documentation_category.id })
      .order(:position)
  end

  it "stores all links from the index topic" do
    expect(sidebar_links.pluck(:href, :topic_id)).to contain_exactly(
      ["/t/#{doc_topic.slug}/#{doc_topic.id}", doc_topic.id],
      ["/t/#{doc_topic_two.slug}/#{doc_topic_two.id}", doc_topic_two.id],
      ["/t/#{other_category_topic.slug}/#{other_category_topic.id}", other_category_topic.id],
      ["/t/#{invisible_topic.slug}/#{invisible_topic.id}", invisible_topic.id],
      ["https://example.com/docs", nil],
    )
  end

  it "exposes only valid links in the sidebar structure" do
    structure = documentation_category.reload.doc_categories_index.sidebar_structure

    expect(structure.length).to eq(1)
    links = structure.first[:links]

    expect(links.map { |l| l[:topic_id] }).to contain_exactly(
      doc_topic.id,
      doc_topic_two.id,
    )
  end
end
