# frozen_string_literal: true

module ::DocCategories::Reports
  class MissingTopicsReport
    def initialize(report)
      @report = report

      @report.dates_filtering = false
      @report.modes = [:table]
      @report.data = []
    end

    def run
      return unless filters = set_filters
      set_labels(filters)
      set_data(filters)
    end

    private

    def set_filters
      return if (doc_category_ids = Category.doc_category_ids).blank?

      doc_categories = Category.where(id: doc_category_ids)
      doc_category_choices =
        doc_categories.map { |category| { id: category.id, name: category.name } }
      if doc_category_choices.size > 1
        doc_category_choices.prepend({ id: -1, name: I18n.t("js.category.all") })
      end

      category_id = @report.filters[:doc_category].to_i if @report.filters[:doc_category].present?
      category_id ||= doc_category_choices.first[:id]

      @report.add_filter(
        "doc_category",
        type: "list",
        choices: doc_category_choices,
        default: category_id,
        allow_any: false,
        auto_insert_none_item: false,
      )

      doc_categories =
        doc_categories.filter { |category| category.id == category_id } if category_id != -1
      return if doc_categories.blank?

      include_topic_from_subcategories = false

      if doc_categories.any? { |category| Category.subcategory_ids(category.id).present? }
        include_topic_from_subcategories = @report.filters[:include_topic_from_subcategories]
        include_topic_from_subcategories =
          !!ActiveRecord::Type::Boolean.new.cast(include_topic_from_subcategories)
        @report.add_filter(
          "include_topic_from_subcategories",
          type: "bool",
          default: include_topic_from_subcategories,
        )
      end

      { categories: doc_categories, include_topic_from_subcategories: }
    end

    def set_labels(filters)
      @report.labels = [
        {
          type: :topic,
          properties: {
            title: :title,
            id: :id,
          },
          title: I18n.t("reports.doc_categories_missing_topics.labels.topic"),
        },
      ]

      if filters[:categories].size > 1
        @report.labels << {
          type: :link,
          properties: %i[index_category_url index_category_name],
          title: I18n.t("reports.doc_categories_missing_topics.labels.index_category"),
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
        indexed_topic_ids = index&.valid_sidebar_topic_ids || []

        # existing topics
        topic_query =
          TopicQuery.new(
            Discourse.system_user,
            { limit: false, no_subcategories: !include_topic_from_subcategories },
          )

        index_topic_id = category.doc_index_topic_id

        existing_topic_ids = topic_query.list_category_topic_ids(category)
        missing_topic_ids = existing_topic_ids - indexed_topic_ids - [index_topic_id]

        data +=
          Topic
            .where(id: missing_topic_ids, visible: true)
            .pluck(:id, :title)
            .map do |id, title|
              {
                id:,
                title:,
                index_category_id: category.id,
                index_category_name: category.name,
                index_category_url: "/c/#{category.id}",
              }
            end
      end

      @report.data = data
    end
  end
end
