# frozen_string_literal: true

class AddAutoIndexToDocCategories < ActiveRecord::Migration[7.2]
  def change
    add_column :doc_categories_indexes,
               :auto_index_include_subcategories,
               :boolean,
               default: false,
               null: false
    add_column :doc_categories_sidebar_sections, :auto_index, :boolean, default: false, null: false
    add_column :doc_categories_sidebar_links, :auto_indexed, :boolean, default: false, null: false
  end
end
