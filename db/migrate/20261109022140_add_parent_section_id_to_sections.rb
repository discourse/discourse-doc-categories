# frozen_string_literal: true
class AddParentSectionIdToSections < ActiveRecord::Migration[8.1]
  def change
    add_column :doc_categories_sidebar_sections, :parent_section_id, :integer
    add_index :doc_categories_sidebar_sections, :parent_section_id
  end
end
