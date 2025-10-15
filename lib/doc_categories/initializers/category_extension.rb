# frozen_string_literal: true

module ::DocCategories
  module Initializers
    module CategoryExtension
      def self.prepended(base)
        base.has_one :doc_categories_index,
                     class_name: "DocCategories::Index",
                     foreign_key: :category_id,
                     dependent: :destroy
      end
    end
  end
end
