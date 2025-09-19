# frozen_string_literal: true

module DocCategories
  module CategoriesControllerExtension
    private

    def category_params
      super.tap do |permitted|
        if params.has_key?(:doc_index_topic_id)
          permitted[:doc_index_topic_id] = params[:doc_index_topic_id]
        end
      end
    end
  end
end
