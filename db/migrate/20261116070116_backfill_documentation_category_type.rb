# frozen_string_literal: true

class BackfillDocumentationCategoryType < ActiveRecord::Migration[8.0]
  def up
    # The visual editor stores -1 as its index topic ID, including for auto-indexes.
    execute <<~SQL
      INSERT INTO category_custom_fields (category_id, name, value, created_at, updated_at)
      SELECT indexes.category_id, 'doc_categories_documentation', 't', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM doc_categories_indexes indexes
      JOIN categories ON categories.id = indexes.category_id
      WHERE indexes.index_topic_id = -1
        AND NOT EXISTS (
          SELECT 1
          FROM category_custom_fields fields
          WHERE fields.category_id = indexes.category_id
            AND fields.name = 'doc_categories_documentation'
        )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
