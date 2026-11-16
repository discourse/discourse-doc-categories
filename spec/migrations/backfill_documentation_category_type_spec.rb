# frozen_string_literal: true

require_relative "../../db/migrate/20261116070116_backfill_documentation_category_type"

RSpec.describe BackfillDocumentationCategoryType do
  it "adds Documentation membership for visual indexes without overwriting or duplicating fields" do
    field = DocCategories::Categories::Types::Documentation::CUSTOM_FIELD
    visual_index = Fabricate(:doc_categories_index, index_topic_id: -1)
    auto_index = Fabricate(:doc_categories_index, index_topic_id: -1)
    Fabricate(:doc_categories_sidebar_section, index: auto_index, auto_index: true)
    topic_index = Fabricate(:doc_categories_index)
    disabled_index = DocCategories::Index.create!(category: Fabricate(:category))
    opted_out_index = Fabricate(:doc_categories_index, index_topic_id: -1)
    opted_out_index.category.upsert_custom_fields(field => false)

    migration = described_class.new
    migration.suppress_messages { 2.times { migration.up } }

    expect(CategoryCustomField.where(name: field).pluck(:category_id, :value)).to contain_exactly(
      [visual_index.category_id, "t"],
      [auto_index.category_id, "t"],
      [opted_out_index.category_id, "f"],
    )
    expect(topic_index.reload).to be_mode_topic
    expect(disabled_index.reload).to be_mode_none
  end
end
