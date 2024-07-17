# frozen_string_literal: true

DocCategories::Engine.routes.draw do
  # define routes here
end

Discourse::Application.routes.draw { mount ::DocCategories::Engine, at: "/" }
