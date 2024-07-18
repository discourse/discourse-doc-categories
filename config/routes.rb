# frozen_string_literal: true

DocCategories::Engine.routes.draw do
  scope GlobalSetting.docs_path do
    get "/" => "docs_legacy#redirect_to_topic", :constraints => ::DocCategories::DocsLegacyConstraint.new
    get ".json" => "docs_legacy#redirect_to_topic", :constraints => ::DocCategories::DocsLegacyConstraint.new
  end
end

Discourse::Application.routes.draw { mount ::DocCategories::Engine, at: "/" }
