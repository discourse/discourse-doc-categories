# frozen_string_literal: true

require "rails_helper"

describe SiteSerializer do
  fab!(:user)
  let(:guardian) { Guardian.new(user) }

  before do
    GlobalSetting.stubs(:docs_path).returns("docs")

    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_docs_legacy_enabled = true
  end

  it "returns correct default value" do
    data = described_class.new(Site.new(guardian), scope: guardian, root: false).as_json

    expect(data[:docs_legacy_path]).to eq("docs")
  end

  it "returns custom path based on global setting" do
    GlobalSetting.stubs(:docs_path).returns("custom_path")
    data = described_class.new(Site.new(guardian), scope: guardian, root: false).as_json

    expect(data[:docs_legacy_path]).to eq("custom_path")
  end

  it "is not serialized if docs legacy mode is disabled" do
    SiteSetting.doc_categories_docs_legacy_enabled = false

    data = described_class.new(Site.new(guardian), scope: guardian, root: false).as_json

    expect(data.has_key?(:docs_legacy_path)).to eq(false)
  end
end
