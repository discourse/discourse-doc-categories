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

    def mode_none?
      index_topic_id.nil?
    end

    def mode_direct?
      index_topic_id == INDEX_TOPIC_ID_DIRECT
    end

    def mode_topic?
      index_topic_id.present? && index_topic_id > 0
    end

    def sidebar_structure
      sections =
        sidebar_sections.includes(sidebar_links: { topic: :category }).group_by(&:parent_section_id)
      serialize_sections(sections.fetch(nil, []), sections).map(&:last)
    end

    def auto_index_section
      sidebar_sections.find_by(auto_index: true)
    end

    def auto_index_enabled?
      mode_direct? && auto_index_section.present?
    end

    # Returns an array of category IDs to source topics from for auto-indexing.
    def matching_category_ids
      if auto_index_include_subcategories
        ::Category.subcategory_ids(category_id)
      else
        [category_id]
      end
    end

    def valid_topic(topic)
      return nil if topic.blank?
      return nil if topic.private_message?
      return nil if topic.trashed?
      return nil unless topic.visible?

      topic
    end

    def sidebar_topic_linked?(topic)
      DocCategories::SidebarLink
        .joins(:sidebar_section)
        .where(sidebar_section: { index_id: id })
        .exists?(topic: topic)
    end

    def replace_sidebar_sections!(sections)
      topic_ids = section_topic_ids(sections).uniq
      topic_titles = ::Topic.where(id: topic_ids).pluck(:id, :title).to_h
      auto_indexed_topic_ids =
        DocCategories::SidebarLink
          .auto_indexed
          .joins(:sidebar_section)
          .where(sidebar_section: { index_id: id })
          .pluck(:topic_id)
          .to_set

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

    def serialize_sections(roots, sections)
      roots.filter_map do |section|
        children = serialize_sections(sections.fetch(section.id, []), sections)
        links =
          section.sidebar_links.filter_map do |link|
            data = serialize_link(link)
            [link.position, data] if data
          end
        next if children.empty? && links.empty? && !section.auto_index?

        data = { id: section.id, text: section.title }
        data[:auto_index] = true if section.auto_index?
        if children.empty?
          data[:links] = links.map(&:last)
        else
          entries = links.map { |position, link| [position, link.merge(type: "link")] }
          entries.concat(
            children.map { |position, child| [position, child.merge(type: "section")] },
          )
          data[:items] = entries.sort_by(&:first).map(&:last)
        end
        [section.position, data]
      end
    end

    def serialize_link(link)
      referenced_topic = link.topic
      return if referenced_topic && !topic_category_visible?(referenced_topic)

      topic = valid_topic(referenced_topic)
      text = link.title.presence || topic&.title
      href = link.href.presence || topic&.relative_url
      return if text.blank? || href.blank?

      result = { text:, href: }
      if link.topic_id.present?
        result[:topic_id] = link.topic_id
        result[:topic_title] = topic&.title
        result[:custom_title] = link.title.present?
      end
      result[:auto_indexed] = true if link.auto_indexed?
      result
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
      !topic.private_message? &&
        (topic.category_id == category_id || topic.category&.read_restricted? == false)
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
