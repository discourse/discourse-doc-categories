# frozen_string_literal: true

module DocCategories
  class SidebarSectionSerializer < ApplicationSerializer
    attributes :id, :text, :type, :links, :items

    def text
      object.title.to_s
    end

    def type
      "section"
    end

    def include_type?
      @options[:nested]
    end

    def links
      @options.fetch(:links).map(&:last)
    end

    def include_links?
      @options.fetch(:children).empty?
    end

    def items
      (@options.fetch(:links) + @options.fetch(:children)).sort_by(&:first).map(&:last)
    end

    def include_items?
      @options.fetch(:children).present?
    end
  end
end
