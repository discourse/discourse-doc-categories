# frozen_string_literal: true

module DocCategories
  class IndexStructureRefresher
    include Service::Base

    params do
      attribute :category_id, :integer

      validates :category_id, presence: true
    end

    transaction do
      step :lock_category
      model :index
      policy :is_topic_mode
      only_if(:invalid_index_topic) { step :remove_index }
      only_if(:index_retained) do
        model :topic
        step :require_index_topic_body
        model :raw_sections, :parse_first_post, optional: true
        model :linked_topics, optional: true
        model :built_sections, :build_sections, optional: true
        step :replace_sections
      end
    end

    step :publish_changes
    only_if(:invalid_index_topic) { step :ensure_valid_topic }

    private

    def lock_category(params:)
      Index.lock_categories(params.category_id)
    end

    def fetch_index(params:)
      DocCategories::Index.includes(index_topic: :shared_draft).find_by(
        category_id: params.category_id,
      )
    end

    def is_topic_mode(index:)
      index.mode_topic?
    end

    def invalid_index_topic(index:)
      !index.sidebar_available?
    end

    def remove_index(index:)
      index.destroy!
    end

    def index_retained(index:)
      index.persisted?
    end

    def ensure_valid_topic
      fail!("index topic is no longer valid")
    end

    def fetch_topic(index:)
      index.index_topic
    end

    def require_index_topic_body(topic:)
      fail!("first post has no content") if topic.first_post&.cooked.blank?
    end

    def parse_first_post(topic:)
      Array(DocCategories::DocIndexTopicParser.new(topic.first_post.cooked).sections)
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
      DocCategories::Action::PublishSidebarChanges.call(category_ids: [index.category_id])
    end

    def fetch_linked_topics(raw_sections:)
      topic_ids =
        raw_sections
          .flat_map { |section| section[:links] }
          .filter_map { |link| DocCategories::Url.extract_topic_id_from_url(link[:href]) }
          .uniq

      ::Topic.where(id: topic_ids).includes(:category, :shared_draft).index_by(&:id)
    end

    def build_sections(index:, raw_sections:, linked_topics:)
      raw_sections.filter_map do |section|
        links =
          section[:links].filter_map do |link|
            href = link[:href]
            next if href.blank?

            link_text = link[:text]

            topic_id = DocCategories::Url.extract_topic_id_from_url(href)
            target_topic =
              (index.sidebar_visible_topic(linked_topics[topic_id]) if topic_id.present?)
            has_explicit_title = link_text.present? && link_text != href
            text = has_explicit_title ? link_text : (target_topic&.title || href)

            { text: text, href: href, topic_id: target_topic&.id }
          end

        next if links.blank?

        { text: section[:text], links: links }
      end
    end
  end
end
