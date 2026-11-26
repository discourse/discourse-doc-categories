# frozen_string_literal: true

module DocCategories
  class IndexSaver
    include Service::Base

    params do
      attribute :category_id, :integer
      attribute :sections
      attribute :force_direct, :boolean, default: false

      validates :category_id, presence: true

      def sections_error
        return if sections.nil?
        return invalid_sections unless sections.is_a?(Array)

        validate_sections(sections, 1, { sections: 0 })
      end

      def built_sections(auto_index_section_id: nil)
        roots = (sections || []).map(&:symbolize_keys)
        # The existing section ID is the only way to retain the stored designation.
        auto_index_position =
          if auto_index_section_id
            roots.index do |section|
              section[:id].to_s == auto_index_section_id.to_s &&
                section_items(section).none? { |item| item.symbolize_keys[:type] == "section" }
            end
          end

        roots.filter_map.with_index do |section, position|
          build_section(
            section,
            allow_untitled: position.zero?,
            auto_index: position == auto_index_position,
          )
        end
      end

      def referenced_topic_ids(items)
        items
          .flat_map do |item|
            if item.key?(:items)
              referenced_topic_ids(item[:items])
            else
              [item[:topic_id], DocCategories::Url.extract_topic_id_from_url(item[:href])]
            end
          end
          .compact
          .uniq
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

          if (depth > 1 || children.present?) && section[:title].to_s.strip.blank?
            return invalid_sections
          end

          if children.present? && (error = validate_sections(children, depth + 1, counts))
            return error
          end
        end
        nil
      end

      def build_section(section, allow_untitled: false, auto_index: false)
        title = section[:title].to_s.strip.first(SidebarSection::MAX_TITLE_LENGTH)
        return if title.blank? && !allow_untitled

        items =
          section_items(section).filter_map do |raw_item|
            item = raw_item.symbolize_keys
            item[:type] == "section" ? build_section(item) : build_link(item)
          end

        return if items.blank? && !auto_index

        { title:, items:, auto_index: }
      end

      def build_link(link)
        title = link[:title].to_s.strip.first(SidebarLink::MAX_TITLE_LENGTH).presence
        href = link[:href].to_s.strip.first(SidebarLink::MAX_HREF_LENGTH)
        return if href.blank?

        topic_id = SidebarLink.referenced_topic_id(link[:topic_id].presence&.to_i, href)
        return if title.blank? && topic_id.blank?

        { title:, href:, topic_id: }
      end
    end

    transaction do
      model :category
      model :index, optional: true
      policy :not_topic_managed
      step :parse_and_validate_sections
      model :built_sections, :build_sections, optional: true
      step :validate_topic_visibility

      only_if(:removing_index) { step :remove_index }
      only_if(:saving_sections) do
        model :saved_index, :save_index
        step :replace_sections
      end
    end

    only_if(:index_changed) { step :publish_changes }
    model :index_structure, :build_response, optional: true

    private

    def fetch_category(params:)
      ::Category.lock.find_by(id: params.category_id)
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
    end

    def build_sections(params:, index:)
      auto_index_section_id = index.auto_index_section&.id if index&.mode_direct?
      params.built_sections(auto_index_section_id:)
    end

    def validate_topic_visibility(params:, built_sections:, category:)
      topics =
        ::Topic
          .with_deleted
          .where(id: params.referenced_topic_ids(built_sections))
          .includes(:category, :shared_draft)
      unless topics.all? { |topic| TopicEligibility.allowed?(topic, category_id: category.id) }
        fail!(I18n.t("doc_categories.errors.private_topic"))
      end
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

    def save_index(category:, index:)
      index_topic_id = Index::INDEX_TOPIC_ID_DIRECT
      return Index.create(category:, index_topic_id:) if index.nil?

      index.update(index_topic_id:)
      index
    end

    def replace_sections(built_sections:, saved_index:)
      saved_index.replace_sidebar_sections!(built_sections)
    end

    def index_changed(built_sections:, index:)
      built_sections.present? || index&.destroyed?
    end

    def publish_changes(category:)
      DocCategories::Action::PublishSidebarChanges.call(category_ids: [category.id])
    end

    def build_response(category:)
      index = DocCategories::Index.find_by(category:)
      DocCategories::IndexSerializer.new(index, root: false).as_json&.dig(:sections)&.as_json
    end
  end
end
