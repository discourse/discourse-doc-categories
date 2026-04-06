# frozen_string_literal: true

module DocCategories
  class IndexSaver
    MAX_SECTIONS = 50
    MAX_LINKS_PER_SECTION = 200

    def initialize(category)
      @category = category
    end

    def save_sections!(sections_data)
      if sections_data.blank?
        index = DocCategories::Index.find_by(category_id: @category.id)
        if index && !index.mode_topic?
          index.sidebar_sections.destroy_all
          index.destroy!
          @category.association(:doc_categories_index).reset
          Site.clear_cache
          @category.publish_category
        end
        return
      end

      index = DocCategories::Index.find_or_initialize_by(category_id: @category.id)
      return if index.mode_topic?

      index.index_topic_id = DocCategories::Index::INDEX_TOPIC_ID_DIRECT

      validate_limits!(sections_data)
      sections = build_sections(sections_data)

      topic_ids = sections.flat_map { |s| s[:links].filter_map { |l| l[:topic_id] } }.uniq
      topic_titles = ::Topic.where(id: topic_ids).pluck(:id, :title).to_h

      ActiveRecord::Base.transaction do
        index.save! if index.new_record?
        index.sidebar_sections.destroy_all

        sections.each_with_index do |section, section_position|
          section_record =
            index.sidebar_sections.create!(title: section[:title], position: section_position)

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
            )
          end
        end

        index.touch
      end
      Site.clear_cache
      @category.publish_category
    end

    private

    def validate_limits!(sections_data)
      if sections_data.size > MAX_SECTIONS
        raise Discourse::InvalidParameters.new(
                I18n.t("doc_categories.errors.too_many_sections", max: MAX_SECTIONS),
              )
      end

      sections_data.each do |section|
        links = section.try(:[], :links) || section.try(:[], "links") || []
        if links.size > MAX_LINKS_PER_SECTION
          raise Discourse::InvalidParameters.new(
                  I18n.t("doc_categories.errors.too_many_links", max: MAX_LINKS_PER_SECTION),
                )
        end
      end
    end

    def build_sections(sections_data)
      sections_data.filter_map do |section_param|
        section_param = section_param.to_h.with_indifferent_access
        title = section_param[:title].to_s.strip.first(255)
        next if title.blank?

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

        next if links.blank?

        { title: title, links: links }
      end
    end
  end
end
