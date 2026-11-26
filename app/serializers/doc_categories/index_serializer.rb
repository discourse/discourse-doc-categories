# frozen_string_literal: true

module DocCategories
  class IndexSerializer < ApplicationSerializer
    attributes :sections

    def sections
      object.sidebar_structure(include_empty: @options[:include_empty])
    end

    def include_sections?
      object&.sidebar_available?
    end
  end
end
