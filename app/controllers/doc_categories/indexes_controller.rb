# frozen_string_literal: true

module ::DocCategories
  class IndexesController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_admin

    def topics
      category = ::Category.find_by(id: params[:category_id])
      raise Discourse::NotFound if category.blank?

      include_subcategories = ActiveRecord::Type::Boolean.new.cast(params[:include_subcategories])

      topic_query =
        TopicQuery.new(current_user, { limit: false, no_subcategories: !include_subcategories })

      topic_ids = topic_query.list_category_topic_ids(category)

      topics =
        Topic
          .where(id: topic_ids, visible: true)
          .order(:title)
          .pluck(:id, :title, :slug)
          .map { |id, title, slug| { id:, title:, slug: } }

      render json: { topics: }
    end

    def update
      category = ::Category.find_by(id: params[:category_id])
      raise Discourse::NotFound if category.blank?

      index = DocCategories::Index.find_by(category_id: category.id)
      if index&.mode_topic?
        raise Discourse::InvalidAccess.new(
          "index managed by a topic",
                nil,
                custom_message: "doc_categories.errors.index_topic_managed",
              )
      end

      sections_params =
        params.permit(sections: [:title, { links: %i[title href icon type topic_id] }]).fetch(
          :sections,
          [],
        )

      DocCategories::IndexSaver.new(category).save_sections!(sections_params)

      render json: success_json
    end
  end
end
