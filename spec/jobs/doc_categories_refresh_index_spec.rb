# frozen_string_literal: true

describe Jobs::DocCategoriesRefreshIndex do
  fab!(:category, :category_with_definition)

  subject(:job) { described_class.new }

  it "raises when the category id is missing" do
    expect { job.execute({}) }.to raise_error(Discourse::InvalidParameters)
  end

  it "delegates to the index refresher" do
    allow(DocCategories::IndexStructureRefresher).to receive(:call).and_call_original

    job.execute(category_id: category.id)

    expect(DocCategories::IndexStructureRefresher).to have_received(:call).with(
      params: {
        category_id: category.id,
      },
    )
  end
end
