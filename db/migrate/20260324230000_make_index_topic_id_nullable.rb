# frozen_string_literal: true

class MakeIndexTopicIdNullable < ActiveRecord::Migration[7.2]
  def change
    change_column_null :doc_categories_indexes, :index_topic_id, true
  end
end
