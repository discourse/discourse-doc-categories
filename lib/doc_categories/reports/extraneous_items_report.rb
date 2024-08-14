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

      if filters[:categories].size > 1
        @report.labels << {
          type: :link,
          properties: %i[index_category_url index_category_name],
          title: I18n.t("reports.doc_categories_extraneous_items.labels.index_category"),
        }
      end
    end

    def set_data(filters)
      filters => { categories:, include_topic_from_subcategories: }

      data = []

      categories.each do |category|
        # existing topics
        topic_query =
          TopicQuery.new(
            Discourse.system_user,
            { limit: false, no_subcategories: !include_topic_from_subcategories },
          )

        existing_topic_ids = topic_query.list_category_topic_ids(category)
        invisible_topic_ids = Topic.where(id: existing_topic_ids, visible: false).pluck(:id)
        existing_topic_ids -= invisible_topic_ids

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
                    if invisible_topic_ids.include?(topic_id)
                      :topic_not_visible
                    else
                      :other_category
                    end
                  elsif route.present?
                    :not_a_topic
                  else
                    :external
                  end

                {
                  title: link[:text] || link[:href],
                  href:,
                  reason:,
                  index_category_id: category.id,
                  index_category_name: category.name,
                  index_category_url: "/c/#{category.id}",
                }
              end
            end
            &.uniq
        indexed_links ||= []

        data += indexed_links
      end

      @report.data = data
    end
  end
end
