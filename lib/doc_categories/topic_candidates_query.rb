# frozen_string_literal: true

module DocCategories
  class TopicCandidatesQuery
    def initialize(
      user:,
      category:,
      include_subcategories: false,
      excluded_topic_ids: [],
      search: ""
    )
      @user = user
      @category = category
      @include_subcategories = include_subcategories
      @excluded_topic_ids = excluded_topic_ids
      @search = search
    end

    def scope
      category_ids =
        @include_subcategories ? ::Category.subcategory_ids(@category.id) : [@category.id]
      category_ids = TopicEligibility.categories(@category.id).where(id: category_ids).select(:id)

      candidates =
        ::Topic
          .secured(@user.guardian)
          .where(category_id: category_ids, visible: true, archetype: Archetype.default)
          .where.not(id: ::SharedDraft.select(:topic_id))
          .where.not(
            id: ::Category.where(id: category_ids).where.not(topic_id: nil).select(:topic_id),
          )
          .where.not(id: @excluded_topic_ids.uniq)
          .order(:title, :id)
      if @search.present?
        candidates =
          candidates.where("topics.title ILIKE ?", "%#{::Topic.sanitize_sql_like(@search)}%")
      end
      candidates
    end
  end
end
