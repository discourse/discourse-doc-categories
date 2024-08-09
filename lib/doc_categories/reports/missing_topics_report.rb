# frozen_string_literal: true

module ::DocCategories::Reports
  class MissingTopicsReport
    def initialize(report)
      @report = report

      @report.dates_filtering = false
      @report.modes = [:table]
      @report.labels = [
        {
          type: :topic,
          properties: {
            title: :title,
            id: :id,
          },
          title: I18n.t("reports.top_referred_topics.labels.topic"),
        },
      ]
      @report.data = []
    end

    def run
      return unless filters = set_filters
      set_data(filters)
    end

    private

    def set_filters
      return unless (doc_category_ids = Category.doc_category_ids).present?

      doc_category_choices =
        Category.where(id: doc_category_ids).pluck(:id, :name).map { |id, name| { id:, name: } }

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

      category = Category.find_by(id: category_id)
      return if category.blank?
      return unless category.doc_category?

      include_topic_from_subcategories = false

      if Category.subcategory_ids(category_id).present?
        include_topic_from_subcategories = @report.filters[:include_topic_from_subcategories]
        include_topic_from_subcategories =
          !!ActiveRecord::Type::Boolean.new.cast(include_topic_from_subcategories)
        @report.add_filter(
          "include_topic_from_subcategories",
          type: "bool",
          default: include_topic_from_subcategories,
        )
      end

      { category:, include_topic_from_subcategories: }
    end

    def set_data(filters)
      filters => { category:, include_topic_from_subcategories: }

      # topics listed in the index
      index_topic_id = category.doc_index_topic_id
      indexed_topic_ids =
        Topic
          .find_by(id: index_topic_id)
          &.yield_self do |index_topic|
            DocCategories::DocIndexTopicParser.new(index_topic.first_post.cooked).sections
          end
          &.flat_map do |section|
            section[:links].filter_map do |link|
              DocCategories::Url.extract_topic_id_from_url(link[:href]) if link[:href].present?
            end
          end
          &.uniq
      indexed_topic_ids ||= []

      # existing topics
      topic_query =
        TopicQuery.new(
          Discourse.system_user,
          { limit: false, no_subcategories: !include_topic_from_subcategories },
        )

      existing_topic_ids = topic_query.list_category_topic_ids(category)
      missing_topic_ids = existing_topic_ids - indexed_topic_ids - [index_topic_id]

      @report.data +=
        Topic
          .where(id: missing_topic_ids, visible: true)
          .pluck(:id, :title)
          .map { |id, title| { id:, title: } }
    end
  end
end
