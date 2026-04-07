# frozen_string_literal: true

module ::DocCategories
  class IndexesController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_admin

    MAX_TOPICS = 5000

    def topics
      category = ::Category.find_by(id: params[:category_id])
      raise Discourse::NotFound if category.blank?

      include_subcategories = ActiveRecord::Type::Boolean.new.cast(params[:include_subcategories])

      topic_query =
        TopicQuery.new(current_user, { limit: false, no_subcategories: !include_subcategories })

      topic_ids = topic_query.list_category_topic_ids(category)

      visible_scope = Topic.where(id: topic_ids, visible: true).order(:title)
      total_count = visible_scope.count

      topics =
        visible_scope
          .limit(MAX_TOPICS)
          .pluck(:id, :title, :slug)
          .map { |id, title, slug| { id:, title:, slug: } }

      render json: { topics:, total_count: }
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

      had_auto_index_section = index&.auto_index_section.present?

      sections_params =
        params.permit(
          sections: [:title, :auto_index, { links: %i[title href icon topic_id] }],
        ).fetch(:sections, [])

      if params.key?(:auto_index_include_subcategories)
        idx = index || DocCategories::Index.find_or_initialize_by(category_id: category.id)
        idx.update!(
          auto_index_include_subcategories:
            ActiveRecord::Type::Boolean.new.cast(params[:auto_index_include_subcategories]),
        )
      end

      DocCategories::IndexSaver.new(category).save_sections!(sections_params)

      # If an auto-index section was just created, run sync inline to backfill existing topics
      current_index = DocCategories::Index.find_by(category_id: category.id)
      if !had_auto_index_section && current_index&.auto_index_section.present?
        DocCategories::AutoIndexer::Sync.call(params: { index_id: current_index.id })
        current_index.reload
      end

      structure = current_index&.sidebar_structure&.as_json
      render json: success_json.merge(index_structure: structure)
    end
  end
end
