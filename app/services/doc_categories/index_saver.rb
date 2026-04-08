# frozen_string_literal: true

module DocCategories
  class IndexSaver
    include Service::Base

    MAX_SECTIONS = DocCategories::Index::MAX_SECTIONS
    MAX_LINKS_PER_SECTION = DocCategories::Index::MAX_LINKS_PER_SECTION

    params do
      attribute :category_id, :integer
      attribute :sections, :array
      attribute :force_direct, :boolean, default: false
      attribute :force_sync, :boolean, default: false
      attribute :auto_index_include_subcategories

      validates :category_id, presence: true
    end

    model :category
    model :index, optional: true

    only_if(:force_direct_requested) { step :convert_to_direct_mode }

    policy :not_topic_managed
    step :capture_old_auto_index_section_id
    step :parse_and_validate_sections
    step :update_subcategory_setting

    transaction { step :save_sections }

    step :publish_changes
    step :determine_sync_needed

    only_if(:should_sync_auto_index) { step :sync_auto_index }

    step :build_response

    private

    def fetch_category(params:)
      ::Category.find_by(id: params.category_id)
    end

    def fetch_index(category:)
      DocCategories::Index.find_by(category_id: category.id)
    end

    def force_direct_requested(params:)
      params.force_direct
    end

    def convert_to_direct_mode(index:)
      return if index.nil? || !index.mode_topic?
      index.update!(index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT)
    end

    def not_topic_managed(index:)
      index.nil? || !index.mode_topic?
    end

    def capture_old_auto_index_section_id(index:)
      context[:old_auto_index_section_id] = index&.auto_index_section&.id
    end

    def parse_and_validate_sections(params:)
      sections_data = params.sections

      if sections_data.blank?
        context[:built_sections] = nil
        context[:sections_data] = []
        return
      end

      unless sections_data.is_a?(Array)
        return(
          fail!(
            I18n.t("doc_categories.errors.invalid_sections", default: "sections must be an array"),
          )
        )
      end

      sections_data = sections_data.map { |s| s.to_h.with_indifferent_access }

      if sections_data.size > MAX_SECTIONS
        return fail!(I18n.t("doc_categories.errors.too_many_sections", max: MAX_SECTIONS))
      end

      sections_data.each do |section|
        links = section[:links] || []
        if links.size > MAX_LINKS_PER_SECTION
          return fail!(I18n.t("doc_categories.errors.too_many_links", max: MAX_LINKS_PER_SECTION))
        end
      end

      context[:built_sections] = build_sections(sections_data).presence
      context[:sections_data] = sections_data
    end

    def update_subcategory_setting(params:, category:)
      return if params.auto_index_include_subcategories.nil?

      new_value = ActiveRecord::Type::Boolean.new.cast(params.auto_index_include_subcategories)
      idx = DocCategories::Index.find_or_initialize_by(category_id: category.id)
      context[:subcategory_setting_changed] = idx.auto_index_include_subcategories != new_value
      if context[:subcategory_setting_changed]
        idx.update!(auto_index_include_subcategories: new_value)
      end
    end

    def save_sections(category:, index:)
      built_sections = context[:built_sections]

      if built_sections.nil?
        destroy_index!(category, index)
        return
      end

      idx = DocCategories::Index.find_or_initialize_by(category_id: category.id)
      idx.index_topic_id = DocCategories::Index::INDEX_TOPIC_ID_DIRECT

      topic_ids = built_sections.flat_map { |s| s[:links].filter_map { |l| l[:topic_id] } }.uniq
      topic_titles = ::Topic.where(id: topic_ids).pluck(:id, :title).to_h

      # Preserve auto-indexed topic IDs so they survive the destroy/recreate cycle
      auto_indexed_topic_ids = collect_auto_indexed_topic_ids(idx)

      idx.save! if idx.new_record?
      idx.sidebar_sections.destroy_all

      built_sections.each_with_index do |section, section_position|
        section_record =
          idx.sidebar_sections.create!(
            title: section[:title],
            position: section_position,
            auto_index: section[:auto_index] || false,
          )

        section[:links].each_with_index do |link, link_position|
          # If the title matches the topic title, store nil (auto title)
          title = link[:title]
          title = nil if link[:topic_id] && title == topic_titles[link[:topic_id]]

          section_record.sidebar_links.create!(
            title: title,
            href: link[:href],
            icon: link[:icon],
            topic_id: link[:topic_id],
            position: link_position,
            auto_indexed:
              link[:topic_id].present? && auto_indexed_topic_ids.include?(link[:topic_id]),
          )
        end
      end

      idx.touch
      context[:index_changed] = true
    end

    def publish_changes(category:)
      return unless context[:index_changed]
      Site.clear_cache
      category.publish_category
    end

    def determine_sync_needed(params:, category:)
      idx = DocCategories::Index.find_by(category_id: category.id)
      return if idx&.auto_index_section.blank?

      context[:sync_index] = idx

      sections_data = (params.sections || []).map { |s| s.to_h.with_indifferent_access }
      incoming_auto =
        sections_data.find { |s| ActiveRecord::Type::Boolean.new.cast(s[:auto_index]) }
      incoming_id = incoming_auto&.dig(:id).presence&.to_i

      context[:should_sync] = params.force_sync || context[:subcategory_setting_changed] ||
        incoming_id.nil? || incoming_id != context[:old_auto_index_section_id]
    end

    def should_sync_auto_index
      context[:should_sync]
    end

    def sync_auto_index
      idx = context[:sync_index]
      return if idx.nil?

      DocCategories::AutoIndexer::Sync.call(params: { index_id: idx.id })
    end

    def build_response(category:)
      current_index = DocCategories::Index.find_by(category_id: category.id)
      context[:index_structure] = current_index&.sidebar_structure&.as_json
    end

    def destroy_index!(category, index)
      idx = index || DocCategories::Index.find_by(category_id: category.id)
      return unless idx && !idx.mode_topic?

      idx.sidebar_sections.destroy_all
      idx.destroy!
      category.association(:doc_categories_index).reset
      context[:index_changed] = true
    end

    def collect_auto_indexed_topic_ids(index)
      return Set.new unless index.persisted?

      DocCategories::SidebarLink
        .auto_indexed
        .joins(:sidebar_section)
        .where(sidebar_section: { index_id: index.id })
        .where.not(topic_id: nil)
        .pluck(:topic_id)
        .to_set
    end

    def build_sections(sections_data)
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
end
