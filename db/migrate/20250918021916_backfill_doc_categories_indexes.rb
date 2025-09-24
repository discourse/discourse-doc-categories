# frozen_string_literal: true

class BackfillDocCategoriesIndexes < ActiveRecord::Migration[7.0]
  def up
    execute <<~SQL
      INSERT INTO doc_categories_indexes (category_id, index_topic_id, created_at, updated_at)
      SELECT ccf.category_id, ccf.value::bigint, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM category_custom_fields ccf
      JOIN topics t ON t.id = ccf.value::bigint
      WHERE ccf.name = 'doc_category_index_topic'
        AND t.category_id = ccf.category_id
        AND NOT EXISTS (
          SELECT 1
          FROM doc_categories_indexes existing
          WHERE existing.category_id = ccf.category_id
        )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
