# frozen_string_literal: true

describe Jobs::DocCategoriesRefreshIndex do
  fab!(:category, :category_with_definition)

  subject(:job) { described_class.new }

  it "raises when the category id is missing" do
    expect { job.execute({}) }.to raise_error(Discourse::InvalidParameters)
  end

  it "delegates to the index refresher" do
    refresher = instance_spy(DocCategories::IndexStructureRefresher)
    allow(DocCategories::IndexStructureRefresher).to receive(:new).with(category.id).and_return(
      refresher,
    )

    job.execute(category_id: category.id)

    expect(refresher).to have_received(:refresh!)
  end
end
