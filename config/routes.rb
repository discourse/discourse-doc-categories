# frozen_string_literal: true

DocCategories::Engine.routes.draw do
  scope GlobalSetting.docs_path do
    get "/" => "docs_legacy#redirect_url", :constraints => ::DocCategories::DocsLegacyConstraint.new
    get ".json" => "docs_legacy#redirect_url",
        :constraints => ::DocCategories::DocsLegacyConstraint.new
  end

  get "knowledge-explorer" => "docs_legacy#redirect_url",
      :constraints => ::DocCategories::DocsLegacyConstraint.new
end

Discourse::Application.routes.draw { mount ::DocCategories::Engine, at: "/" }
