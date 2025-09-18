# frozen_string_literal: true

module DocCategories
  class SidebarLink < ActiveRecord::Base
    self.table_name = "doc_categories_sidebar_links"

    belongs_to :sidebar_section,
               class_name: "DocCategories::SidebarSection",
               foreign_key: :doc_categories_sidebar_section_id,
               inverse_of: :sidebar_links

    belongs_to :topic, class_name: "::Topic", optional: true

    validates :doc_categories_sidebar_section_id, presence: true
    validates :position, presence: true, uniqueness: { scope: :doc_categories_sidebar_section_id }
    validates :title, length: { maximum: 255 }, allow_blank: true
    validates :href, length: { maximum: 2000 }, allow_blank: true
  end
end
