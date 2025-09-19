# frozen_string_literal: true

module Jobs
  class DocCategoriesRefreshIndex < ::Jobs::Base
    def execute(args)
      category_id = args[:category_id]
      raise Discourse::InvalidParameters.new(:category_id) if category_id.blank?

      DocCategories::IndexStructureRefresher.new(category_id).refresh!
    end
  end
end
