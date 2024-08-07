# frozen_string_literal: true

class ::DocCategories::DocsLegacyConstraint
  def matches?(_request)
    ::DocCategories.legacyMode?
  end
end
