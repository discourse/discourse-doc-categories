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

      return if topic.deleted_at.blank? && topic.deleted_by_id.blank?

      errors.add(:topic_id, "cannot reference a deleted topic")
    end
  end
end

# == Schema Information
#
# Table name: doc_categories_sidebar_links
#
#  id                                :bigint           not null, primary key
#  href                              :text
#  position                          :integer          not null
#  title                             :string
#  created_at                        :datetime         not null
#  updated_at                        :datetime         not null
#  doc_categories_sidebar_section_id :bigint           not null
#  topic_id                          :bigint
#
# Indexes
#
#  idx_doc_categories_links_on_section_id_and_position  (doc_categories_sidebar_section_id,position) UNIQUE
#  index_doc_categories_sidebar_links_on_topic_id       (topic_id)
#
