# frozen_string_literal: true

module DocCategories
  class SidebarLink < ActiveRecord::Base
    self.table_name = "doc_categories_sidebar_links"

    belongs_to :sidebar_section,
               class_name: "DocCategories::SidebarSection",
               foreign_key: :doc_categories_sidebar_section_id,
               inverse_of: :sidebar_links

    belongs_to :topic, optional: true

    validates :doc_categories_sidebar_section_id, presence: true
    validates :position, presence: true, uniqueness: { scope: :doc_categories_sidebar_section_id }
    validates :title, length: { maximum: 255 }
    validates :href, length: { maximum: 2000 }
    validate :target_present
    validate :topic_not_deleted

    private

    def target_present
      return if topic_id.present? || href.present?

      errors.add(:base, "must include either a topic or href")
    end

    def topic_not_deleted
      return if topic.nil?

      return unless topic.deleted_at.present? || topic.deleted_by_id.present?

      errors.add(:topic_id, "cannot reference a deleted topic")
    end
  end
end
