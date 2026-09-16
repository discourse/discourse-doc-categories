# frozen_string_literal: true

class AddIconToSidebarLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :doc_categories_sidebar_links, :icon, :string, limit: 100
  end
end
