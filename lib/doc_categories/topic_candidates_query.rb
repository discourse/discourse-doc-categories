# frozen_string_literal: true

module DocCategories
  class TopicCandidatesQuery
    def initialize(user:, category:, include_subcategories: false)
      @user = user
      @category = category
      @include_subcategories = include_subcategories
    end

    def scope
      category_ids =
        @include_subcategories ? ::Category.subcategory_ids(@category.id) : [@category.id]

      ::Topic
        .secured(@user.guardian)
        .where(category_id: category_ids, visible: true, archetype: Archetype.default)
        .where.not(
          id: ::Category.where(id: category_ids).where.not(topic_id: nil).select(:topic_id),
        )
        .order(:title, :id)
    end
  end
end
