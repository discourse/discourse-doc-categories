# frozen_string_literal: true

module ::DocCategories::Reports
  class ExtraneousItemsReport < MissingTopicsReport
    private

    def set_labels(filters)
      @report.labels = [
        {
          type: :link,
          properties: %i[href title],
          title: I18n.t("reports.doc_categories_extraneous_items.labels.item"),
        },
        {
          type: :text,
          property: :reason,
          title: I18n.t("reports.doc_categories_extraneous_items.labels.reason"),
        },
      ]
    end

    def set_data(filters)
      filters => { category:, include_topic_from_subcategories: }

      # existing topics
      topic_query =
        TopicQuery.new(
          Discourse.system_user,
          { limit: false, no_subcategories: !include_topic_from_subcategories },
        )

      existing_topic_ids = topic_query.list_category_topic_ids(category)

      # topics listed in the index
      index_topic_id = category.doc_index_topic_id
      indexed_links =
        Topic
          .find_by(id: index_topic_id)
          &.yield_self do |index_topic|
            DocCategories::DocIndexTopicParser.new(index_topic.first_post.cooked).sections
          end
          &.flat_map do |section|
            section[:links].filter_map do |link|
              href = link[:href]
              topic_id = DocCategories::Url.extract_topic_id_from_url(href)
              route = Discourse.route_for(href) unless topic_id

              next nil if topic_id && existing_topic_ids.include?(topic_id)

              reason =
                if topic_id.present?
                  :other_category
                elsif route.present?
                  :not_a_topic
                else
                  :external
                end

              { title: link[:text] || link[:href], href:, reason: }
            end
          end
          &.uniq
      indexed_links ||= []

      @report.data = indexed_links
    end
  end
end
