# frozen_string_literal: true

module ::DocCategories
  class DocsLegacyController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :check_xhr, only: %i[redirect_url redirect_to_homepage]

    def redirect_url
      # if there is a `topic` parameter provided. try to redirect to the corresponding topic
      if params.include?(:topic)
        topic = Topic.find_by(id: params[:topic].to_i)
        begin
          guardian.ensure_can_see!(topic)
        rescue Discourse::InvalidAccess => ex
          raise(SiteSetting.detailed_404 ? ex : Discourse::NotFound)
        end

        url = topic.relative_url
        url += ".json" if request.format.json?

        redirect_to "#{url}#{prepare_url_query_params}"
        return
      end

      # if a topic was not provided try to redirect to the default homepage, if one was set
      redirect_to_homepage
    end

    private

    def redirect_to_homepage
      if SiteSetting.doc_categories_homepage
        redirect_to "#{SiteSetting.doc_categories_homepage}#{prepare_url_query_params}"
        return
      end

      # fallback to 404
      raise Discourse::NotFound
    end

    def prepare_url_query_params
      query_parameters_list = request.query_parameters.except(:topic)

      return "" if query_parameters_list.empty?

      query_parameters_string =
        query_parameters_list.map { |name, value| "#{name}=#{value}" }.join("&")

      "?#{query_parameters_string}"
    end
  end
end
