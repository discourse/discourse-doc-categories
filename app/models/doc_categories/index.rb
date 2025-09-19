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
      sidebar_sections
        .includes(sidebar_links: :topic)
        .map do |section|
          links =
            section.sidebar_links.filter_map do |link|
              topic = link.topic
              next unless valid_link_target?(topic)

              text = link.title.presence || topic.title

              { text: text, href: topic.relative_url, topic_id: topic.id }
            end

          next if links.blank?

          { text: section.title, links: links }
        end
        .compact
    end

    def valid_sidebar_topic_ids
      sidebar_sections
        .includes(sidebar_links: :topic)
        .flat_map do |section|
          section.sidebar_links.select { |link| valid_link_target?(link.topic) }
        end
        .filter_map(&:topic_id)
        .uniq
    end

    private

    def index_topic_matches_category
      return if index_topic_id.blank? || category_id.blank?
      return if index_topic&.category_id == category_id

      errors.add(:index_topic_id, "must belong to the same category")
    end

    def valid_link_target?(topic)
      return false if topic.blank?
      return false if topic.private_message?
      return false if topic.trashed?
      return false unless topic.visible?
      return false unless topic.category_id == category_id

      true
    end
  end
end
