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
        index =
          DocCategories::Index.includes(sidebar_sections: :sidebar_links).find_by(
            category_id: category.id,
          )
        next if index.blank?

        links =
          DocCategories::SidebarLink
            .joins(sidebar_section: :index)
            .includes(:topic)
            .where(doc_categories_indexes: { category_id: category.id })

        links.each do |link|
          reason = extraneous_reason(link, category, include_topic_from_subcategories)
          next if reason.blank?

          data << {
            title: link.title.presence || link.href,
            href: link.href,
            reason: reason,
            index_category_id: category.id,
            index_category_name: category.name,
            index_category_url: "/c/#{category.id}",
          }
        end
      end

      @report.data = data
    end

    def extraneous_reason(link, category, include_topic_from_subcategories)
      topic = link.topic

      if topic.present?
        if topic.category_id != category.id &&
             !(
               include_topic_from_subcategories &&
                 Category.subcategory_ids(category.id).include?(topic.category_id)
             )
          return :other_category
        end
        return :topic_not_visible unless topic.visible?

        return nil
      end

      route = Discourse.route_for(link.href)

      return :not_a_topic if route.present?

      :external
    rescue ActionController::RoutingError
      :external
    end
  end
end
