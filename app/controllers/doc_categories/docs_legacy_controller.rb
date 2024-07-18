# frozen_string_literal: true

module ::DocCategories
  class DocsLegacyController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :check_xhr, only: [:redirect_to_topic]

    def redirect_to_topic
      topic = Topic.find_by(id: params[:topic].to_i)
      raise Discourse::NotFound unless topic

      begin
        guardian.ensure_can_see!(topic)
      rescue Discourse::InvalidAccess => ex
        raise(SiteSetting.detailed_404 ? ex : Discourse::NotFound)
      end

      url = topic.relative_url
      url += ".json" if request.format.json?

      separator = "?"
      request
        .query_parameters
        .except(:topic_id)
        .each do |name, value|
          url += "#{separator || "?"}#{name}=#{value}"
          separator = "&"
        end

      redirect_to url
    end
  end
end
