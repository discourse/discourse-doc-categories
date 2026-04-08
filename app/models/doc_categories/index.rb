# frozen_string_literal: true

module DocCategories
  class Index < ActiveRecord::Base
    self.table_name = "doc_categories_indexes"

    # Sentinel value for index_topic_id indicating visual editor (direct) mode.
    # NULL = no index configured (MODE_NONE), -1 = visual editor (MODE_DIRECT),
    # positive integer = topic-based index (MODE_TOPIC).
    INDEX_TOPIC_ID_DIRECT = -1
    MAX_SECTIONS = 50
    MAX_LINKS_PER_SECTION = 200

    belongs_to :category, class_name: "::Category"
    belongs_to :index_topic, class_name: "::Topic", optional: true

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
      sidebar_sections
        .includes(sidebar_links: :topic)
        .map do |section|
          links =
            section.sidebar_links.filter_map do |link|
              # for text: always use link[:title] if present, otherwise use topic title if topic is valid
              # for href: always use link[:href] if present, otherwise use topic relative_url if topic is valid

              topic = valid_topic(link.topic)

              text = link.title.presence || (topic&.title)
              href = link.href.presence || (topic&.relative_url)
              next if text.blank? || href.blank?
              result = { text:, href: }
              result[:icon] = link.icon if link.icon.present?
              if link.topic_id.present?
                result[:topic_id] = link.topic_id
                result[:topic_title] = topic&.title
                result[:custom_title] = link.title.present?
              end
              result[:auto_indexed] = true if link.auto_indexed?
              result
            end

          next if links.blank? && !section.auto_index?

          section_result = { id: section.id, text: section.title, links: links }
          section_result[:auto_index] = true if section.auto_index?
          section_result
        end
        .compact
    end

    def auto_index_section
      sidebar_sections.find_by(auto_index: true)
    end

    def auto_index_enabled?
      mode_direct? && auto_index_section.present?
    end

    # Returns an array of category IDs to source topics from for auto-indexing.
    def matching_category_ids
      ids = [category_id]
      ids.concat(::Category.subcategory_ids(category_id)) if auto_index_include_subcategories
      ids
    end

    def valid_topic(topic)
      return nil if topic.blank?
      return nil if topic.private_message?
      return nil if topic.trashed?
      return nil unless topic.visible?

      topic
    end

    private

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
