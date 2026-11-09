# frozen_string_literal: true

module DocCategories
  class SidebarSection < ActiveRecord::Base
    self.table_name = "doc_categories_sidebar_sections"

    belongs_to :index,
               class_name: "DocCategories::Index",
               foreign_key: :index_id,
               inverse_of: :sidebar_sections

    belongs_to :parent_section, class_name: "DocCategories::SidebarSection", optional: true

    has_many :sidebar_links,
             -> { order(:position) },
             class_name: "DocCategories::SidebarLink",
             foreign_key: :sidebar_section_id,
             inverse_of: :sidebar_section,
             dependent: :destroy

    validates :index_id, presence: true
    validates :position, presence: true, uniqueness: { scope: %i[index_id parent_section_id] }
    validates :title, length: { maximum: 255 }, allow_blank: true
    validate :parent_belongs_to_index, if: :parent_section_id?
    validate :only_one_auto_index_section_per_index, if: :auto_index?

    private

    def parent_belongs_to_index
      errors.add(:parent_section, :invalid) if parent_section&.index_id != index_id
    end

    def only_one_auto_index_section_per_index
      existing = self.class.where(index_id: index_id, auto_index: true).where.not(id: id).exists?
      if existing
        errors.add(:auto_index, I18n.t("doc_categories.errors.only_one_auto_index_section"))
      end
    end
  end
end

# == Schema Information
#
# Table name: doc_categories_sidebar_sections
#
#  id                :bigint           not null, primary key
#  auto_index        :boolean          default(FALSE), not null
#  position          :integer          not null
#  title             :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  index_id          :bigint           not null
#  parent_section_id :bigint
#
# Indexes
#
#  idx_doc_categories_sections_on_parent_and_position          (index_id,parent_section_id,position) UNIQUE NULLS NOT DISTINCT
#  index_doc_categories_sidebar_sections_on_parent_section_id  (parent_section_id)
#
