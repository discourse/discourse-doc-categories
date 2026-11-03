# frozen_string_literal: true

module ::DocCategories
  class IndexesController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_admin
    before_action :ensure_index_editor_enabled

    MAX_TOPICS = 50

    def topics
      scope = topic_candidates
      render json: { topics: topic_rows(scope.limit(MAX_TOPICS)), total_count: scope.count }
    end

    def unindexed_topics
      DocCategories::UnindexedTopicsList.call(service_params) do
        on_success do |topics:, total_count:, params:|
          render json: {
                   topics:
                     ActiveModel::ArraySerializer.new(
                       topics,
                       each_serializer: DocCategories::UnindexedTopicSerializer,
                       root: false,
                     ).as_json,
                   total_count: total_count,
                   page: params.page.to_i,
                   per_page: DocCategories::UnindexedTopicsList::PAGE_SIZE,
                 }
        end
        on_failed_contract do |contract|
          raise Discourse::InvalidParameters.new(contract.errors.attribute_names.first)
        end
        on_model_not_found(:category) { raise Discourse::NotFound }
        on_failed_policy(:can_list_topics) { raise Discourse::InvalidAccess }
        on_failure { render json: failed_json, status: :unprocessable_entity }
      end
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

    private

    def topic_candidates
      category = ::Category.find(params[:category_id])
      guardian.ensure_can_see!(category)

      TopicCandidatesQuery.new(
        user: current_user,
        category: category,
        include_subcategories: ActiveRecord::Type::Boolean.new.cast(params[:include_subcategories]),
      ).scope
    end

    def topic_rows(scope)
      scope
        .pluck(:id, :title, :slug, :category_id)
        .map { |id, title, slug, category_id| { id:, title:, slug:, category_id: } }
    end

    def ensure_index_editor_enabled
      return if SiteSetting.doc_categories_index_editor

      # Allow edits to categories already in direct mode
      index = DocCategories::Index.find_by(category_id: params[:category_id])
      raise Discourse::InvalidAccess if index.nil? || !index.mode_direct?
    end
  end
end
