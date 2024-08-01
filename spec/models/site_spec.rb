# frozen_string_literal: true

require "rails_helper"

describe Site do
  context "when the plugin enabled status is changed" do
    it "invalidates the site cache when the plugin is turned on" do
      described_class.expects(:clear_cache).at_least_once
      SiteSetting.doc_categories_enabled = true
    end

    it "invalidates the site cache when the plugin is turned off" do
      SiteSetting.doc_categories_enabled = true

      described_class.expects(:clear_cache).at_least_once
      SiteSetting.doc_categories_enabled = false
    end
  end
end
