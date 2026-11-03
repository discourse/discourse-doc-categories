# frozen_string_literal: true

module DocCategories
  class UnindexedTopicSerializer < ApplicationSerializer
    attributes :id, :title, :slug, :category_id
  end
end
