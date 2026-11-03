# frozen_string_literal: true

class UsePartialUniqueIndexForIndexTopicId < ActiveRecord::Migration[7.2]
  def up
    remove_index :doc_categories_indexes,
                 name: :idx_doc_categories_indexes_on_index_topic_id,
                 if_exists: true

    add_index :doc_categories_indexes,
              :index_topic_id,
              unique: true,
              name: :idx_doc_categories_indexes_on_index_topic_id,
              where: "index_topic_id IS NOT NULL AND index_topic_id != -1"
  end

  def down
    # Set direct-mode sentinel values to NULL so the full unique index can be
    # created. Direct mode didn't exist before this migration.
    execute "UPDATE doc_categories_indexes SET index_topic_id = NULL WHERE index_topic_id = -1"

    remove_index :doc_categories_indexes,
                 name: :idx_doc_categories_indexes_on_index_topic_id,
                 if_exists: true

    add_index :doc_categories_indexes,
              :index_topic_id,
              unique: true,
              name: :idx_doc_categories_indexes_on_index_topic_id
  end
end
