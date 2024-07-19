# frozen_string_literal: true

class ::DocCategories::DocsLegacyConstraint
  def matches?(_request)
    SiteSetting.doc_categories_docs_legacy_enabled
  end
end
