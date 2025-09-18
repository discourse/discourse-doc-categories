# frozen_string_literal: true

class CreateDocCategoriesTables < ActiveRecord::Migration[7.0]
  def change
    create_table :doc_categories_indexes do |t|
      t.bigint :category_id, null: false
      t.bigint :index_topic_id, null: false
      t.timestamps
    end

    add_index :doc_categories_indexes,
              :category_id,
              unique: true,
              name: :idx_doc_categories_indexes_on_category_id
    add_index :doc_categories_indexes,
              :index_topic_id,
              unique: true,
              name: :idx_doc_categories_indexes_on_index_topic_id

    create_table :doc_categories_sidebar_sections do |t|
      t.bigint :doc_categories_index_id, null: false
      t.string :title
      t.integer :position, null: false
      t.timestamps
    end

    add_index :doc_categories_sidebar_sections,
              [:doc_categories_index_id, :position],
              unique: true,
              name: :idx_doc_categories_sections_on_index_id_and_position

    create_table :doc_categories_sidebar_links do |t|
      t.bigint :doc_categories_sidebar_section_id, null: false
      t.string :title
      t.text :href
      t.integer :position, null: false
      t.bigint :topic_id
      t.timestamps
    end

    add_index :doc_categories_sidebar_links,
              [:doc_categories_sidebar_section_id, :position],
              unique: true,
              name: :idx_doc_categories_links_on_section_id_and_position
    add_index :doc_categories_sidebar_links, :topic_id
  end
end
