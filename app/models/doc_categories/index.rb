# frozen_string_literal: true

module DocCategories
  class Index < ActiveRecord::Base
    self.table_name = "doc_categories_indexes"

    belongs_to :category, class_name: "::Category"
    belongs_to :index_topic, class_name: "::Topic"

    has_many :sidebar_sections,
             -> { order(:position) },
             class_name: "DocCategories::SidebarSection",
             foreign_key: :index_id,
             inverse_of: :index,
             dependent: :destroy

    validates :category_id, presence: true, uniqueness: true
    validates :index_topic_id, presence: true, uniqueness: true

    validate :index_topic_matches_category

    def sidebar_structure
      sidebar_sections
        .includes(sidebar_links: :topic)
        .map do |section|
          links =
            section.sidebar_links.filter_map do |link|
              # for text: always use link[:title] if present, otherwise use topic title if topic is valid
              # for href: always use link[:href] if present, otherwise use topic relative_url if topic is valid

              topic = valid_topic(topic)

              text = link.title.presence || (topic&.title)
              href = link.href.presence || (topic&.relative_url)
              next if text.blank? || href.blank?
              { text:, href: }
            end

          next if links.blank?

          { text: section.title, links: links }
        end
        .compact
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
#  id             :bigint           not null, primary key
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  category_id    :bigint           not null
#  index_topic_id :bigint           not null
#
# Indexes
#
#  idx_doc_categories_indexes_on_category_id     (category_id) UNIQUE
#  idx_doc_categories_indexes_on_index_topic_id  (index_topic_id) UNIQUE
#
