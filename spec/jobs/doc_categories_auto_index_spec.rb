# frozen_string_literal: true

describe Jobs::DocCategoriesAutoIndex do
  subject(:job) { described_class.new }

  it "raises when action is missing" do
    expect { job.execute({}) }.to raise_error(Discourse::InvalidParameters)
  end

  it "raises when action is invalid" do
    expect { job.execute(action: "invalid") }.to raise_error(Discourse::InvalidParameters)
  end

  it "calls AddTopic service for the add action" do
    allow(DocCategories::AutoIndexer::AddTopic).to receive(:call).and_return(true)

    job.execute(action: "add", topic_id: 1)

    expect(DocCategories::AutoIndexer::AddTopic).to have_received(:call).with(
      params: {
        topic_id: 1,
      },
    )
  end

  it "raises when add action is missing topic_id" do
    expect { job.execute(action: "add") }.to raise_error(Discourse::InvalidParameters)
  end

  it "calls RemoveTopic service for the remove action" do
    allow(DocCategories::AutoIndexer::RemoveTopic).to receive(:call).and_return(true)

    job.execute(action: "remove", topic_id: 1)

    expect(DocCategories::AutoIndexer::RemoveTopic).to have_received(:call).with(
      params: {
        topic_id: 1,
      },
    )
  end

  it "raises when remove action is missing topic_id" do
    expect { job.execute(action: "remove") }.to raise_error(Discourse::InvalidParameters)
  end

  it "calls Sync service for the sync action" do
    allow(DocCategories::AutoIndexer::Sync).to receive(:call).and_return(true)

    job.execute(action: "sync", index_id: 1)

    expect(DocCategories::AutoIndexer::Sync).to have_received(:call).with(params: { index_id: 1 })
  end

  it "raises when sync action is missing index_id" do
    expect { job.execute(action: "sync") }.to raise_error(Discourse::InvalidParameters)
  end
end
