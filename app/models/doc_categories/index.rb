# frozen_string_literal: true

module DocCategories
  class Index < ActiveRecord::Base
    self.table_name = "doc_categories_indexes"

    belongs_to :category, class_name: "::Category"
    belongs_to :index_topic, class_name: "::Topic"

    has_many :sidebar_sections,
             -> { order(:position) },
             class_name: "DocCategories::SidebarSection",
             foreign_key: :doc_categories_index_id,
             inverse_of: :index,
             dependent: :destroy

    validates :category_id, presence: true, uniqueness: true
    validates :index_topic_id, presence: true, uniqueness: true

    validate :index_topic_matches_category

    def sidebar_structure
      sidebar_sections.includes(:sidebar_links).map do |section|
        links =
          section.sidebar_links.map do |link|
            { text: link.title, href: link.href, topic_id: link.topic_id }
          end.compact

        next if links.blank?

        { text: section.title, links: links }
      end.compact
    end

    private

    def index_topic_matches_category
      return if index_topic_id.blank? || category_id.blank?
      return if index_topic&.category_id == category_id

      errors.add(:index_topic_id, "must belong to the same category")
    end
  end
end
