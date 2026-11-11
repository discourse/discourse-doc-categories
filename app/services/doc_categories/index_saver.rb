# frozen_string_literal: true

module DocCategories
  class IndexSaver
    include Service::Base

    params do
      attribute :category_id, :integer
      attribute :sections
      attribute :force_direct, :boolean, default: false
      attribute :force_sync, :boolean, default: false
      attribute :auto_index_include_subcategories, :boolean

      validates :category_id, presence: true

      def sections_error
        return if sections.nil?
        return invalid_sections unless sections.is_a?(Array)

        validate_sections(sections, 1, { sections: 0, auto_index: 0 })
      end

      def built_sections
        build_sections(sections || [])
      end

      private

      def invalid_sections
        I18n.t("doc_categories.errors.invalid_sections")
      end

      def section_items(section)
        return section[:items] if section.key?(:items)

        links = section[:links] || []
        return unless links.is_a?(Array) && links.all?(Hash)

        links.map { |link| link.symbolize_keys.merge(type: "link") }
      end

      def validate_sections(sections, depth, counts)
        if depth > DocCategories::Index::MAX_SECTION_DEPTH
          return(
            I18n.t(
              "doc_categories.errors.section_depth_limit",
              max: DocCategories::Index::MAX_SECTION_DEPTH,
            )
          )
        end

        sections.each do |raw_section|
          return invalid_sections unless raw_section.is_a?(Hash)
          if (counts[:sections] += 1) > DocCategories::Index::MAX_SECTIONS
            return(
              I18n.t(
                "doc_categories.errors.too_many_sections",
                max: DocCategories::Index::MAX_SECTIONS,
              )
            )
          end

          section = raw_section.symbolize_keys
          items = section_items(section)
          return invalid_sections unless items.is_a?(Array) && items.all?(Hash)
          items = items.map(&:symbolize_keys)
          unless items.all? { |item| %w[link section].include?(item[:type]) }
            return invalid_sections
          end

          children, links = items.partition { |item| item[:type] == "section" }
          if links.size > DocCategories::Index::MAX_LINKS_PER_SECTION
            return(
              I18n.t(
                "doc_categories.errors.too_many_links",
                max: DocCategories::Index::MAX_LINKS_PER_SECTION,
              )
            )
          end

          auto_index = ActiveRecord::Type::Boolean.new.cast(section[:auto_index])
          return invalid_sections if depth > 1 && (section[:title].to_s.strip.blank? || auto_index)
          if children.present? && (section[:title].to_s.strip.blank? || auto_index)
            return invalid_sections
          end
          if auto_index && (counts[:auto_index] += 1) > 1
            return I18n.t("doc_categories.errors.only_one_auto_index_section")
          end

          if children.present? && (error = validate_sections(children, depth + 1, counts))
            return error
          end
        end
        nil
      end

      def build_sections(sections)
        sections.filter_map.with_index do |section, position|
          build_section(section.symbolize_keys, allow_untitled: position.zero?)
        end
      end

      def build_section(section, allow_untitled: false)
        title = section[:title].to_s.strip.first(255)
        return if title.blank? && !allow_untitled

        items =
          section_items(section).filter_map do |raw_item|
            item = raw_item.symbolize_keys
            item[:type] == "section" ? build_section(item) : build_link(item)
          end

        auto_index = ActiveRecord::Type::Boolean.new.cast(section[:auto_index])
        return if items.blank? && !auto_index

        { id: section[:id], title:, items:, auto_index: auto_index || false }
      end

      def build_link(link)
        title = link[:title].to_s.strip.first(255).presence
        href = link[:href].to_s.strip.first(2000)
        return if href.blank?

        topic_id =
          link[:topic_id].presence&.to_i || DocCategories::Url.extract_topic_id_from_url(href)
        return if title.blank? && topic_id.blank?

        { title:, href:, topic_id: }
      end
    end

    model :category
    model :index, optional: true
    policy :not_topic_managed
    step :parse_and_validate_sections
    step :determine_sync_needed

    transaction do
      only_if(:removing_index) { step :remove_index }
      only_if(:saving_sections) do
        model :saved_index, :save_index
        step :replace_sections
      end
    end

    only_if(:index_changed) { step :publish_changes }
    only_if(:should_sync_auto_index) { step :sync_auto_index }
    step :build_response

    private

    def fetch_category(params:)
      ::Category.find_by(id: params.category_id)
    end

    def fetch_index(category:)
      DocCategories::Index.find_by(category: category)
    end

    def not_topic_managed(index:, params:)
      index.nil? || !index.mode_topic? || params.force_direct
    end

    def parse_and_validate_sections(params:)
      error = params.sections_error
      fail!(error) if error
      context[:built_sections] = params.built_sections
    end

    def determine_sync_needed(params:, index:, built_sections:)
      # The submitted section ID refers to the rows before replacement.
      incoming_id = built_sections.find { |section| section[:auto_index] }&.dig(:id).presence&.to_i
      context[:sync_required] = params.force_sync ||
        (
          !params.auto_index_include_subcategories.nil? &&
            params.auto_index_include_subcategories !=
              (index&.auto_index_include_subcategories || false)
        ) || incoming_id.nil? || incoming_id != index&.auto_index_section&.id
    end

    def removing_index(built_sections:, index:)
      built_sections.empty? && index.present?
    end

    def remove_index(index:, category:)
      index.destroy!
      category.association(:doc_categories_index).reset
    end

    def saving_sections(built_sections:)
      built_sections.present?
    end

    def save_index(params:, category:, index:)
      record = index || DocCategories::Index.new(category: category)
      record.index_topic_id = DocCategories::Index::INDEX_TOPIC_ID_DIRECT
      unless params.auto_index_include_subcategories.nil?
        record.auto_index_include_subcategories = params.auto_index_include_subcategories
      end
      record.save
      record
    end

    def replace_sections(built_sections:, saved_index:)
      saved_index.replace_sidebar_sections!(built_sections)
    end

    def index_changed(built_sections:, index:)
      built_sections.present? || index&.destroyed?
    end

    def publish_changes(category:)
      Site.clear_cache
      category.publish_category
    end

    def should_sync_auto_index(sync_required:, built_sections:, category:)
      sync_required && built_sections.present? &&
        DocCategories::Index.find_by(category: category)&.auto_index_section.present?
    end

    def sync_auto_index(saved_index:)
      DocCategories::AutoIndexer::Sync.call(params: { index_id: saved_index.id })
    end

    def build_response(category:)
      context[:index_structure] = DocCategories::Index
        .find_by(category: category)
        &.sidebar_structure
        &.as_json
    end
  end
end
