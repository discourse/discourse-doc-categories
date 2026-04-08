# frozen_string_literal: true

module DocCategories
  class IndexSaver
    MAX_SECTIONS = DocCategories::Index::MAX_SECTIONS
    MAX_LINKS_PER_SECTION = DocCategories::Index::MAX_LINKS_PER_SECTION

    def initialize(category)
      @category = category
    end

    def save_sections!(sections_data)
      unless sections_data.blank? || sections_data.is_a?(Array)
        raise Discourse::InvalidParameters.new(:sections)
      end

      if sections_data.blank?
        destroy_index!
        return
      end

      index = DocCategories::Index.find_or_initialize_by(category_id: @category.id)
      raise Discourse::InvalidAccess if index.mode_topic?

      index.index_topic_id = DocCategories::Index::INDEX_TOPIC_ID_DIRECT

      sections_data = sections_data.map { |s| s.to_h.with_indifferent_access }
      validate_limits!(sections_data)
      sections = build_sections(sections_data)

      if sections.blank?
        destroy_index!(index: index) if index.persisted?
        return
      end

      topic_ids = sections.flat_map { |s| s[:links].filter_map { |l| l[:topic_id] } }.uniq
      topic_titles = ::Topic.where(id: topic_ids).pluck(:id, :title).to_h

      # Preserve auto-indexed topic IDs so they survive the destroy/recreate cycle
      auto_indexed_topic_ids = collect_auto_indexed_topic_ids(index)

      ActiveRecord::Base.transaction do
        index.save! if index.new_record?
        index.sidebar_sections.destroy_all

        sections.each_with_index do |section, section_position|
          section_record =
            index.sidebar_sections.create!(
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

        index.touch
      end
      Site.clear_cache
      @category.publish_category
    end

    def sync_auto_index_if_needed!(sections_data, old_auto_index_section_id: nil, force: false)
      index = DocCategories::Index.find_by(category_id: @category.id)
      return if index&.auto_index_section.blank?

      sections_data = sections_data&.map { |s| s.to_h.with_indifferent_access } || []
      incoming_auto =
        sections_data.find { |s| ActiveRecord::Type::Boolean.new.cast(s[:auto_index]) }
      incoming_id = incoming_auto&.dig(:id).presence&.to_i

      if force || incoming_id.nil? || incoming_id != old_auto_index_section_id
        DocCategories::AutoIndexer::Sync.call(params: { index_id: index.id })
        index.reload
      end

      index
    end

    private

    def destroy_index!(index: nil)
      index ||= DocCategories::Index.find_by(category_id: @category.id)
      return unless index && !index.mode_topic?

      index.sidebar_sections.destroy_all
      index.destroy!
      @category.association(:doc_categories_index).reset
      Site.clear_cache
      @category.publish_category
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

    def validate_limits!(sections_data)
      if sections_data.size > MAX_SECTIONS
        raise Discourse::InvalidParameters.new(
                I18n.t("doc_categories.errors.too_many_sections", max: MAX_SECTIONS),
              )
      end

      sections_data.each do |section|
        links = section[:links] || []
        if links.size > MAX_LINKS_PER_SECTION
          raise Discourse::InvalidParameters.new(
                  I18n.t("doc_categories.errors.too_many_links", max: MAX_LINKS_PER_SECTION),
                )
        end
      end
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
