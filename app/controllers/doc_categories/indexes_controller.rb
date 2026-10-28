# frozen_string_literal: true

module ::DocCategories
  class IndexesController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    before_action :ensure_admin
    before_action :ensure_index_editor_enabled

    MAX_TOPICS = 50
    MAX_EXCLUDED_TOPICS = Index::MAX_SECTIONS * Index::MAX_LINKS_PER_SECTION

    def topics
      scope = topic_candidates
      render json: { topics: topic_rows(scope.limit(MAX_TOPICS)), total_count: scope.count }
    end

    def unindexed_topics
      excluded_ids = params[:exclude_topic_ids] || []
      unless excluded_ids.is_a?(Array) && excluded_ids.size <= MAX_EXCLUDED_TOPICS &&
               excluded_ids.all? { |id| id.to_s.match?(/\A[1-9]\d{0,18}\z/) }
        raise Discourse::InvalidParameters.new(:exclude_topic_ids)
      end

      excluded_hrefs = params[:exclude_hrefs] || []
      unless excluded_hrefs.is_a?(Array) && excluded_hrefs.size <= MAX_EXCLUDED_TOPICS &&
               excluded_hrefs.all? { |href| href.is_a?(String) && href.length <= 2000 }
        raise Discourse::InvalidParameters.new(:exclude_hrefs)
      end
      excluded_ids =
        excluded_ids.map(&:to_i) +
          excluded_hrefs.filter_map { |href| DocCategories::Url.extract_topic_id_from_url(href) }

      limit = params.fetch(:limit, MAX_TOPICS).to_s
      raise Discourse::InvalidParameters.new(:limit) if ["0", MAX_TOPICS.to_s].exclude?(limit)

      page = params.fetch(:page, 0).to_s
      raise Discourse::InvalidParameters.new(:page) unless page.match?(/\A\d{1,6}\z/)

      search = params[:search].to_s.strip
      raise Discourse::InvalidParameters.new(:search) if search.length > 200

      scope = topic_candidates.where.not(id: excluded_ids.uniq)
      if search.present?
        scope = scope.where("topics.title ILIKE ?", "%#{Topic.sanitize_sql_like(search)}%")
      end

      render json: {
               topics: topic_rows(scope.offset(page.to_i * MAX_TOPICS).limit(limit.to_i)),
               total_count: scope.count,
               page: page.to_i,
               per_page: MAX_TOPICS,
             }
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
      category = ::Category.find_by(id: params[:category_id])
      raise Discourse::NotFound if category.blank?
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
