# frozen_string_literal: true

module DocCategories
  class IndexStructureRefresher
    def initialize(category_id)
      @category_id = category_id
    end

    def refresh!
      index = DocCategories::Index.includes(:index_topic).find_by(category_id: category_id)
      return unless index

      topic = index.index_topic
      if !valid_topic?(topic)
        category_id = index.category_id
        index.destroy!
        publish_changes(category_id)
        return
      end

      first_post = topic.first_post
      return unless first_post&.cooked.present?

      sections = DocCategories::DocIndexTopicParser.new(first_post.cooked).sections
      sections = build_sections(sections)

      ActiveRecord::Base.transaction do
        index.sidebar_sections.destroy_all

        sections.each_with_index do |section, section_position|
          section_record =
            index.sidebar_sections.create!(title: section[:text], position: section_position)

          section[:links].each_with_index do |link, link_position|
            section_record.sidebar_links.create!(
              title: link[:text],
              href: link[:href],
              topic_id: link[:topic_id],
              position: link_position,
            )
          end
        end
      end

      index.touch
      publish_changes(index.category_id)
    end

    private

    attr_reader :category_id

    def build_sections(raw_sections)
      return [] if raw_sections.blank?

      topic_ids =
        raw_sections
          .flat_map { |section| section[:links] }
          .filter_map { |link| DocCategories::Url.extract_topic_id_from_url(link[:href]) }
          .uniq

      topics_by_id = ::Topic.where(id: topic_ids).index_by(&:id)

      raw_sections.filter_map do |section|
        links =
          section[:links].filter_map do |link|
            href = link[:href]
            next if href.blank?

            topic_id = DocCategories::Url.extract_topic_id_from_url(href)
            target_topic = topic_id.present? ? topics_by_id[topic_id] : nil
            text = link[:text].presence || target_topic&.title || href

            { text: text, href: href, topic_id: topic_id }
          end

        next if links.blank?

        { text: section[:text], links: links }
      end
    end

    def valid_topic?(topic)
      return false if topic.blank?
      return false if topic.private_message?
      return false if topic.trashed?
      return false unless topic.category_id == category_id

      true
    end

    def publish_changes(category_id)
      category = ::Category.find_by(id: category_id)
      return unless category

      ::Site.clear_cache
      category.publish_category
    end
  end
end
