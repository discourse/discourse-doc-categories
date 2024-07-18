# frozen_string_literal: true

class ::DocCategories::DocsLegacyConstraint
  def matches?(_request)
    SiteSetting.docs_legacy_enabled
  end
end
