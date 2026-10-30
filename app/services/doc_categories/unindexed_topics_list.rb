# frozen_string_literal: true

module DocCategories
  class UnindexedTopicsList
    include Service::Base

    PAGE_SIZE = 50
    MAX_EXCLUDED_TOPICS = Index::MAX_SECTIONS * Index::MAX_LINKS_PER_SECTION

    params do
      attribute :category_id, :integer
      attribute :include_subcategories, :boolean, default: false
      attribute :exclude_topic_ids, default: -> { [] }
      attribute :exclude_hrefs, default: -> { [] }
      attribute :limit, :string, default: -> { PAGE_SIZE.to_s }
      attribute :page, :string, default: "0"
      attribute :search, :string, default: ""

      before_validation { self.search = search.to_s.strip }

      validates :category_id, presence: true
      validates :limit, inclusion: { in: ->(_) { ["0", PAGE_SIZE.to_s] } }
      validates :page, format: { with: /\A\d{1,6}\z/ }
      validate :valid_exclusions
      validates :search, length: { maximum: 200 }

      def valid_exclusions
        ids = exclude_topic_ids || []
        unless ids.is_a?(Array) && ids.size <= MAX_EXCLUDED_TOPICS &&
                 ids.all? { |id| id.to_s.match?(/\A[1-9]\d{0,18}\z/) }
          errors.add(:exclude_topic_ids, :invalid)
        end

        hrefs = exclude_hrefs || []
        unless hrefs.is_a?(Array) && hrefs.size <= MAX_EXCLUDED_TOPICS &&
                 hrefs.all? { |href| href.is_a?(String) && href.length <= 2000 }
          errors.add(:exclude_hrefs, :invalid)
        end
      end

      def excluded_topic_ids
        Array(exclude_topic_ids || []).map(&:to_i) +
          Array(exclude_hrefs || []).filter_map do |href|
            DocCategories::Url.extract_topic_id_from_url(href)
          end
      end
    end

    model :category
    policy :can_list_topics
    model :candidates, optional: true
    step :count_topics
    model :topics, optional: true

    private

    def fetch_category(params:)
      ::Category.find_by(id: params.category_id)
    end

    def can_list_topics(guardian:, category:)
      guardian.is_admin? && guardian.can_see?(category) && SiteSetting.doc_categories_enabled &&
        (SiteSetting.doc_categories_index_editor || category.doc_categories_index&.mode_direct?)
    end

    def fetch_candidates(params:, category:, guardian:)
      scope =
        TopicCandidatesQuery
          .new(
            user: guardian.user,
            category: category,
            include_subcategories: params.include_subcategories,
          )
          .scope
          .where.not(id: params.excluded_topic_ids.uniq)
      if params.search.present?
        scope = scope.where("topics.title ILIKE ?", "%#{Topic.sanitize_sql_like(params.search)}%")
      end
      scope
    end

    def count_topics(candidates:)
      context[:total_count] = candidates.count
    end

    def fetch_topics(candidates:, params:)
      candidates.offset(params.page.to_i * PAGE_SIZE).limit(params.limit.to_i)
    end
  end
end
