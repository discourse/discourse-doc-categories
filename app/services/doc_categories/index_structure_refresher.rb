# frozen_string_literal: true

module DocCategories
  class IndexStructureRefresher
    include Service::Base

    params do
      attribute :category_id, :integer

      validates :category_id, presence: true
    end

    model :index
    policy :is_topic_mode
    step :ensure_valid_topic
    step :parse_first_post
    step :build_sections

    transaction { step :replace_sections }

    step :publish_changes

    private

    def fetch_index(params:)
      DocCategories::Index.includes(:index_topic).find_by(category_id: params.category_id)
    end

    def is_topic_mode(index:)
      index.mode_topic?
    end

    def ensure_valid_topic(index:)
      topic = index.index_topic

      if topic.blank? || topic.private_message? || topic.trashed? ||
           topic.category_id != index.category_id
        # Topic is no longer valid — destroy the index and publish changes
        category_id = index.category_id
        index.destroy!
        publish_changes_for(category_id)
        return fail!("index topic is no longer valid")
      end

      context[:topic] = topic
    end

    def parse_first_post(topic:)
      first_post = topic.first_post
      return fail!("first post has no content") if first_post&.cooked.blank?

      context[:raw_sections] = DocCategories::DocIndexTopicParser.new(first_post.cooked).sections
    end

    def build_sections(index:, raw_sections:)
      context[:built_sections] = process_raw_sections(raw_sections, index.category_id)
    end

    def replace_sections(index:, built_sections:)
      index.sidebar_sections.destroy_all

      built_sections.each_with_index do |section, section_position|
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

      index.touch
    end

    def publish_changes(index:)
      publish_changes_for(index.category_id)
    end

    def process_raw_sections(raw_sections, category_id)
      return [] if raw_sections.blank?

      topic_ids =
        raw_sections
          .flat_map { |section| section[:links] }
          .filter_map { |link| DocCategories::Url.extract_topic_id_from_url(link[:href]) }
          .uniq

      topics_by_id = ::Topic.where(id: topic_ids).includes(:category).index_by(&:id)

      raw_sections.filter_map do |section|
        links =
          section[:links].filter_map do |link|
            href = link[:href]
            next if href.blank?

            link_text = link[:text]

            topic_id = DocCategories::Url.extract_topic_id_from_url(href)
            target_topic =
              if topic_id.present?
                sidebar_visible_target_topic(topics_by_id[topic_id], category_id)
              end
            has_explicit_title = link_text.present? && link_text != href
            text = has_explicit_title ? link_text : (target_topic&.title || href)

            { text: text, href: href, topic_id: target_topic&.id }
          end

        next if links.blank?

        { text: section[:text], links: links }
      end
    end

    # Kept from `main`: a link may point anywhere, so a topic the reader cannot
    # see must not reach the sidebar, title included. The index's own category is
    # allowed outright; anything else has to be in a category that is not
    # read restricted.
    def sidebar_visible_target_topic(topic, category_id)
      return nil if topic.blank?
      return nil if topic.private_message?
      return nil if topic.trashed?
      return nil if !topic.visible?
      return topic if topic.category_id == category_id
      return nil if topic.category&.read_restricted?

      topic
    end

    def publish_changes_for(category_id)
      category = ::Category.find_by(id: category_id)
      return unless category

      Site.clear_cache
      category.publish_category
    end
  end
end
