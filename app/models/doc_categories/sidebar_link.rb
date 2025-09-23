# frozen_string_literal: true

module DocCategories
  class SidebarLink < ActiveRecord::Base
    self.table_name = "doc_categories_sidebar_links"

    belongs_to :sidebar_section,
               class_name: "DocCategories::SidebarSection",
               foreign_key: :sidebar_section_id,
               inverse_of: :sidebar_links

    belongs_to :topic, optional: true

    before_validation :populate_href_from_topic, if: -> { topic.present? && href.blank? }

    validates :sidebar_section_id, presence: true
    validates :position,
              presence: true,
              uniqueness: {
                scope: :sidebar_section_id,
              },
              numericality: {
                only_integer: true,
                greater_than: -1,
              }
    validates :title, length: { maximum: 255 }
    validates :href, length: { maximum: 2000 }, presence: true
    validate :topic_not_deleted

    private

    def topic_not_deleted
      return if topic.nil?
      return if !topic.trashed?

      errors.add(:topic_id, "cannot reference a deleted topic")
    end

    def populate_href_from_topic
      self.href = topic.relative_url
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
#  sidebar_section_id :bigint           not null
#  topic_id                          :bigint
#
# Indexes
#
#  idx_doc_categories_links_on_section_id_and_position  (doc_categories_sidebar_section_id,position) UNIQUE
#  index_doc_categories_sidebar_links_on_topic_id       (topic_id)
#
