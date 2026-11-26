# frozen_string_literal: true

module DocCategories
  class Index < ActiveRecord::Base
    self.table_name = "doc_categories_indexes"

    # Sentinel value for index_topic_id indicating visual editor (direct) mode.
    # NULL = no index configured (MODE_NONE), -1 = visual editor (MODE_DIRECT),
    # positive integer = topic-based index (MODE_TOPIC).
    INDEX_TOPIC_ID_DIRECT = -1
    MAX_SECTION_DEPTH = 3
    MAX_SECTIONS = 50
    MAX_LINKS_PER_SECTION = 200

    belongs_to :category, class_name: "::Category"
    belongs_to :index_topic, -> { with_deleted }, class_name: "::Topic", optional: true

    has_many :sidebar_sections,
             -> { order(:position) },
             class_name: "DocCategories::SidebarSection",
             foreign_key: :index_id,
             inverse_of: :index,
             dependent: :destroy

    validates :category_id, presence: true, uniqueness: true
    validates :index_topic_id, uniqueness: true, allow_nil: true, unless: :mode_direct?

    validate :index_topic_matches_category, if: :mode_topic?

    def self.lock_categories(category_ids)
      ::Category.where(id: category_ids).order(:id).lock.pluck(:id)
    end

    def mode_none?
      index_topic_id.nil?
    end

    def mode_direct?
      index_topic_id == INDEX_TOPIC_ID_DIRECT
    end

    def mode_topic?
      index_topic_id.present? && index_topic_id > 0
    end

    def sidebar_available?
      !mode_topic? ||
        (
          index_topic.present? && !index_topic.trashed? && !index_topic.private_message? &&
            !index_topic.shared_draft && index_topic.category_id == category_id
        )
    end

    def sidebar_structure(include_empty: false)
      sections = sidebar_sections.includes(sidebar_links: { topic: %i[category shared_draft] }).to_a
      sections_by_parent = sections.group_by(&:parent_section_id)
      topics_by_href = href_topics(sections.flat_map(&:sidebar_links))
      serialize_sections(
        sections_by_parent.fetch(nil, []),
        sections_by_parent,
        topics_by_href,
        include_empty:,
      ).map(&:last)
    end

    def auto_index_section
      sidebar_sections.find_by(auto_index: true)
    end

    def auto_index_enabled?
      mode_direct? && auto_index_section.present?
    end

    # Returns an array of category IDs to source topics from for auto-indexing.
    def matching_category_ids
      ids =
        auto_index_include_subcategories ? ::Category.subcategory_ids(category_id) : [category_id]
      TopicEligibility.categories(category_id).where(id: ids).pluck(:id)
    end

    def valid_topic(topic)
      return nil if topic.blank?
      return nil if topic.private_message?
      return nil if topic.trashed?
      return nil unless topic.visible?

      topic
    end

    def sidebar_topic_linked?(topic)
      return false if !sidebar_available?

      sidebar_links_scope.exists?(topic:) || href_only_topic_ids.include?(topic.id)
    end

    def indexed_topic_ids
      return [] if !sidebar_available?

      topic_ids = sidebar_links_scope.where.not(topic_id: nil).distinct.pluck(:topic_id)
      topic_ids | href_only_topic_ids
    end

    def replace_sidebar_sections!(sections)
      topic_ids = section_topic_ids(sections).uniq
      topic_titles = ::Topic.where(id: topic_ids).pluck(:id, :title).to_h
      auto_indexed_topic_ids = Set.new
      if sections.any? { |section| section[:auto_index] }
        auto_indexed_topic_ids =
          DocCategories::SidebarLink
            .auto_indexed
            .joins(:sidebar_section)
            .where(sidebar_section: { index_id: id })
            .pluck(:topic_id)
            .to_set
      end

      sidebar_sections.destroy_all
      sections.each_with_index do |section, position|
        create_section!(section, nil, position, topic_titles, auto_indexed_topic_ids)
      end

      touch
    end

    def sidebar_visible_topic(topic)
      topic = valid_topic(topic)
      return if topic.nil?

      topic if topic_category_visible?(topic)
    end

    private

    def sidebar_links_scope
      SidebarLink.where(sidebar_section: sidebar_sections.reorder(nil))
    end

    def href_only_topic_ids
      sidebar_links_scope
        .where(topic_id: nil)
        .distinct
        .pluck(:href)
        .filter_map { |href| SidebarLink.referenced_topic_id(nil, href) }
    end

    def href_topics(links)
      topic_ids_by_href =
        links
          .reject { |link| link.topic && link.href == link.topic.relative_url }
          .map(&:href)
          .uniq
          .index_with { |href| SidebarLink.referenced_topic_id(nil, href) }
          .compact
      topics_by_id =
        ::Topic
          .with_deleted
          .where(id: topic_ids_by_href.values.uniq)
          .includes(:category, :shared_draft)
          .index_by(&:id)
      topic_ids_by_href.transform_values { |topic_id| topics_by_id[topic_id] }
    end

    def serialize_sections(roots, sections, topics_by_href, include_empty:, nested: false)
      roots.filter_map do |section|
        children =
          serialize_sections(
            sections.fetch(section.id, []),
            sections,
            topics_by_href,
            include_empty:,
            nested: true,
          )
        links =
          section.sidebar_links.filter_map do |link|
            data = serialize_link(link, topics_by_href, nested: children.present?)
            [link.position, data] if data
          end
        next if children.empty? && links.empty? && !section.auto_index? && !include_empty

        data =
          SidebarSectionSerializer.new(section, root: false, links:, children:, nested:).as_json
        [section.position, data]
      end
    end

    def serialize_link(link, topics_by_href, nested:)
      topic = link.topic
      if [topic, topics_by_href[link.href]].compact.any? { |target| !sidebar_visible_topic(target) }
        return
      end

      data = SidebarLinkSerializer.new(link, root: false, topic:, nested:).as_json
      data if data[:text].present? && data[:href].present?
    end

    def section_topic_ids(sections)
      sections.flat_map do |section|
        section[:items].flat_map do |item|
          item.key?(:items) ? section_topic_ids([item]) : Array(item[:topic_id])
        end
      end
    end

    def create_section!(section, parent, position, topic_titles, auto_indexed_topic_ids)
      record =
        sidebar_sections.create!(
          title: section[:title],
          parent_section: parent,
          position:,
          auto_index: section[:auto_index],
        )
      section[:items].each_with_index do |item, item_position|
        if item.key?(:items)
          create_section!(item, record, item_position, topic_titles, auto_indexed_topic_ids)
        else
          title = item[:title]
          title = nil if item[:topic_id] && title == topic_titles[item[:topic_id]]
          record.sidebar_links.create!(
            **item.slice(:href, :topic_id),
            title:,
            position: item_position,
            auto_indexed:
              item[:topic_id].present? && auto_indexed_topic_ids.include?(item[:topic_id]),
          )
        end
      end
    end

    def topic_category_visible?(topic)
      TopicEligibility.allowed?(topic, category_id: category_id)
    end

    def index_topic_matches_category
      return if index_topic&.category_id == category_id
      errors.add(:index_topic_id, "must belong to the same category")
    end
  end
end

# == Schema Information
#
# Table name: doc_categories_indexes
#
#  id                               :bigint           not null, primary key
#  auto_index_include_subcategories :boolean          default(FALSE), not null
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  category_id                      :bigint           not null
#  index_topic_id                   :bigint
#
# Indexes
#
#  idx_doc_categories_indexes_on_category_id     (category_id) UNIQUE
#  idx_doc_categories_indexes_on_index_topic_id  (index_topic_id) UNIQUE WHERE ((index_topic_id IS NOT NULL) AND (index_topic_id <> '-1'::integer))
#
