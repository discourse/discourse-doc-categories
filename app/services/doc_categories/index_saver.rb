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
        return if sections.blank?
        unless sections.is_a?(Array) && sections.all? { |section| section.is_a?(Hash) }
          return I18n.t("doc_categories.errors.invalid_sections")
        end
        if sections.size > DocCategories::Index::MAX_SECTIONS
          return(
            I18n.t(
              "doc_categories.errors.too_many_sections",
              max: DocCategories::Index::MAX_SECTIONS,
            )
          )
        end
        sections.each do |section|
          links = section.to_h.with_indifferent_access[:links] || []
          unless links.is_a?(Array) && links.all? { |link| link.is_a?(Hash) }
            return I18n.t("doc_categories.errors.invalid_sections")
          end
          if links.size > DocCategories::Index::MAX_LINKS_PER_SECTION
            return(
              I18n.t(
                "doc_categories.errors.too_many_links",
                max: DocCategories::Index::MAX_LINKS_PER_SECTION,
              )
            )
          end
        end
        if sections.count { |section|
             ActiveRecord::Type::Boolean.new.cast(section.to_h.with_indifferent_access[:auto_index])
           } > 1
          I18n.t("doc_categories.errors.only_one_auto_index_section")
        end
      end

      def incoming_auto_index_section_id
        return if sections.blank?

        section =
          Array(sections).find do |candidate|
            ActiveRecord::Type::Boolean.new.cast(
              candidate.to_h.with_indifferent_access[:auto_index],
            )
          end
        section&.to_h&.with_indifferent_access&.dig(:id).presence&.to_i
      end

      def built_sections
        return [] if sections.blank?

        sections_data = Array(sections).map { |section| section.to_h.with_indifferent_access }
        sections_data.filter_map.with_index do |section_param, idx|
          title = section_param[:title].to_s.strip.first(255)
          # First section is allowed to have a blank title (not collapsible in sidebar)
          next if title.blank? && idx > 0

          links = section_param[:links] || []
          links =
            links.filter_map do |link_param|
              link_param = link_param.to_h.with_indifferent_access
              link_title = link_param[:title].to_s.strip.first(255).presence
              link_href = link_param[:href].to_s.strip.first(2000)
              next if link_href.blank?

              topic_id =
                link_param[:topic_id].presence&.to_i ||
                  DocCategories::Url.extract_topic_id_from_url(link_href)

              next if link_title.blank? && topic_id.blank?

              link_icon = link_param[:icon].to_s.strip.first(100).presence

              { title: link_title, href: link_href, icon: link_icon, topic_id: topic_id }
            end

          auto_index = ActiveRecord::Type::Boolean.new.cast(section_param[:auto_index])
          next if links.blank? && !auto_index

          { title: title, links: links, auto_index: auto_index || false }
        end
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
    end

    def determine_sync_needed(params:, index:)
      # The submitted section ID refers to the rows before replacement.
      context[:sync_required] = params.force_sync ||
        (
          !params.auto_index_include_subcategories.nil? &&
            params.auto_index_include_subcategories !=
              (index&.auto_index_include_subcategories || false)
        ) || params.incoming_auto_index_section_id.nil? ||
        params.incoming_auto_index_section_id != index&.auto_index_section&.id
    end

    def removing_index(params:, index:)
      params.built_sections.empty? && index.present?
    end

    def remove_index(index:, category:)
      index.destroy!
      category.association(:doc_categories_index).reset
    end

    def saving_sections(params:)
      params.built_sections.present?
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

    def replace_sections(params:, saved_index:)
      saved_index.replace_sidebar_sections!(params.built_sections)
    end

    def index_changed(params:, index:)
      params.built_sections.present? || index&.destroyed?
    end

    def publish_changes(category:)
      Site.clear_cache
      category.publish_category
    end

    def should_sync_auto_index(sync_required:, params:, category:)
      sync_required && params.built_sections.present? &&
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
