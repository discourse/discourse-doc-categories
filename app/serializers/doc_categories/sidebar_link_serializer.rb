# frozen_string_literal: true

module DocCategories
  class SidebarLinkSerializer < ApplicationSerializer
    attributes :text, :href, :topic_id, :topic_title, :custom_title, :type

    def text
      object.title.presence || @options[:topic]&.title
    end

    def href
      object.href.presence || @options[:topic]&.relative_url
    end

    def topic_title
      @options[:topic]&.title
    end

    def custom_title
      object.title.present?
    end

    def include_topic_id?
      object.topic_id.present?
    end

    alias_method :include_topic_title?, :include_topic_id?
    alias_method :include_custom_title?, :include_topic_id?

    def type
      "link"
    end

    def include_type?
      @options[:nested]
    end
  end
end
