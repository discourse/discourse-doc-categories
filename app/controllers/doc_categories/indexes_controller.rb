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
      DocCategories::IndexSaver.call(service_params) do
        on_success do |index_structure:|
          render json: success_json.merge(index_structure: index_structure)
        end
        on_model_not_found(:category) { raise Discourse::NotFound }
        on_failed_policy(:not_topic_managed) do
          raise Discourse::InvalidAccess.new(
                  "index managed by a topic",
                  nil,
                  custom_message: "doc_categories.errors.index_topic_managed",
                )
        end
        on_failed_step(:parse_and_validate_sections) do |step|
          render json: failed_json.merge(errors: [step.error]), status: :bad_request
        end
        on_failure { render json: failed_json, status: :unprocessable_entity }
      end
    end
  end
end
