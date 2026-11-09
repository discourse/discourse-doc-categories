# frozen_string_literal: true

class ScopeDocCategorySectionPositionsToParent < ActiveRecord::Migration[8.1]
  def up
    change_column :doc_categories_sidebar_sections, :parent_section_id, :bigint
    add_index :doc_categories_sidebar_sections,
              %i[index_id parent_section_id position],
              unique: true,
              nulls_not_distinct: true,
              name: :idx_doc_categories_sections_on_parent_and_position
    remove_index :doc_categories_sidebar_sections,
                 name: :idx_doc_categories_sections_on_index_id_and_position
  end

  def down
    remove_index :doc_categories_sidebar_sections,
                 name: :idx_doc_categories_sections_on_parent_and_position
    execute <<~SQL
      WITH ordered_sections AS (
        SELECT id, row_number() OVER (PARTITION BY index_id ORDER BY position, id) - 1 AS position
        FROM doc_categories_sidebar_sections
      )
      UPDATE doc_categories_sidebar_sections AS sections
      SET position = ordered_sections.position
      FROM ordered_sections
      WHERE sections.id = ordered_sections.id
    SQL
    add_index :doc_categories_sidebar_sections,
              %i[index_id position],
              unique: true,
              name: :idx_doc_categories_sections_on_index_id_and_position
    change_column :doc_categories_sidebar_sections, :parent_section_id, :integer
  end
end
