# frozen_string_literal: true

module DocCategories
  class UnindexedTopicsList
    include Service::Base

    PAGE_SIZE = 50
    MAX_PAGE = 999_999
    MAX_SEARCH_LENGTH = 200
    MAX_EXCLUDED_TOPICS = Index::MAX_SECTIONS * Index::MAX_LINKS_PER_SECTION

    options { attribute :exclude_saved_index, :boolean, default: false }

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
      validates :page, format: { with: /\A\d{1,#{MAX_PAGE.to_s.length}}\z/ }
      validate :valid_exclusions
      validates :search, length: { maximum: MAX_SEARCH_LENGTH }

      def valid_exclusions
        ids = exclude_topic_ids || []
        unless ids.is_a?(Array) && ids.size <= MAX_EXCLUDED_TOPICS &&
                 ids.all? { |id| id.to_s.match?(/\A[1-9]\d{0,18}\z/) }
          errors.add(:exclude_topic_ids, :invalid)
        end

        hrefs = exclude_hrefs || []
        unless hrefs.is_a?(Array) && hrefs.size <= MAX_EXCLUDED_TOPICS &&
                 hrefs.all? { |href|
                   href.is_a?(String) && href.length <= SidebarLink::MAX_HREF_LENGTH
                 }
          errors.add(:exclude_hrefs, :invalid)
        end
      end

      def excluded_topic_ids
        Array(exclude_topic_ids || []).map(&:to_i) +
          Array(exclude_hrefs || []).filter_map do |href|
            SidebarLink.referenced_topic_id(nil, href)
          end
      end

      def offset
        page.to_i * PAGE_SIZE
      end
    end

    model :category
    policy :can_list_topics
    model :candidates, optional: true
    model :total_count, :count_topics
    model :topics, optional: true

    private

    def fetch_category(params:)
      ::Category.find_by(id: params.category_id)
    end

    def can_list_topics(guardian:, category:)
      guardian.is_admin? && guardian.can_see?(category) && SiteSetting.doc_categories_enabled &&
        (SiteSetting.doc_categories_index_editor || category.doc_categories_index&.mode_direct?)
    end

    def fetch_candidates(params:, options:, category:, guardian:)
      excluded_topic_ids = params.excluded_topic_ids
      if options.exclude_saved_index
        excluded_topic_ids |= Array(category.doc_categories_index&.indexed_topic_ids)
      end

      TopicCandidatesQuery.new(
        user: guardian.user,
        category: category,
        include_subcategories: params.include_subcategories,
        excluded_topic_ids:,
        search: params.search,
      ).scope
    end

    def count_topics(candidates:)
      candidates.count
    end

    def fetch_topics(candidates:, params:)
      candidates.offset(params.offset).limit(params.limit.to_i)
    end
  end
end
