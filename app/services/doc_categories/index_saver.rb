# frozen_string_literal: true

module DocCategories
  class IndexSaver
    MAX_SECTIONS = 20
    MAX_LINKS_PER_SECTION = 50

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

      sections = build_sections(sections_data)

      index.save! if index.new_record?
      index.sidebar_sections.destroy_all

      sections.each_with_index do |section, section_position|
        section_record =
          index.sidebar_sections.create!(title: section[:title], position: section_position)

        section[:links].each_with_index do |link, link_position|
          topic_id = DocCategories::Url.extract_topic_id_from_url(link[:href])
          section_record.sidebar_links.create!(
            title: link[:title],
            href: link[:href],
            icon: link[:icon],
            topic_id: topic_id,
            position: link_position,
          )
        end
      end

      index.touch
      Site.clear_cache
      @category.publish_category
    end

    private

    def build_sections(sections_data)
      sections_data
        .first(MAX_SECTIONS)
        .filter_map do |section_param|
          section_param = section_param.to_h.with_indifferent_access
          title = section_param[:title].to_s.strip.first(255)
          next if title.blank?

          links = (section_param[:links] || []).first(MAX_LINKS_PER_SECTION)
          links =
            links.filter_map do |link_param|
              link_param = link_param.to_h.with_indifferent_access
              link_title = link_param[:title].to_s.strip.first(255)
              link_href = link_param[:href].to_s.strip.first(2000)
              next if link_title.blank? || link_href.blank?

              link_icon = link_param[:icon].to_s.strip.first(100).presence

              { title: link_title, href: link_href, icon: link_icon }
            end

          next if links.blank?

          { title: title, links: links }
        end
    end
  end
end
