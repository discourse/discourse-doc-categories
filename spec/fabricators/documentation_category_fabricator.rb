# frozen_string_literal: true

Fabricator(:documentation_category, from: :category_with_definition) do
  custom_fields { { DocCategories::Categories::Types::Documentation::CUSTOM_FIELD => true } }
end
