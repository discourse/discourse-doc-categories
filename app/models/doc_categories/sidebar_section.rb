# frozen_string_literal: true

module DocCategories
  class SidebarSection < ActiveRecord::Base
    self.table_name = "doc_categories_sidebar_sections"

    belongs_to :index,
               class_name: "DocCategories::Index",
               foreign_key: :doc_categories_index_id,
               inverse_of: :sidebar_sections

    has_many :sidebar_links,
             -> { order(:position) },
             class_name: "DocCategories::SidebarLink",
             foreign_key: :doc_categories_sidebar_section_id,
             inverse_of: :sidebar_section,
             dependent: :destroy

    validates :doc_categories_index_id, presence: true
    validates :position, presence: true, uniqueness: { scope: :doc_categories_index_id }
    validates :title, length: { maximum: 255 }, allow_blank: true
  end
end

# == Schema Information
#
# Table name: doc_categories_sidebar_sections
#
#  id                      :bigint           not null, primary key
#  position                :integer          not null
#  title                   :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  doc_categories_index_id :bigint           not null
#
# Indexes
#
#  idx_doc_categories_sections_on_index_id_and_position  (doc_categories_index_id,position) UNIQUE
#
