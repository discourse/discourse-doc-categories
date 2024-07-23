# frozen_string_literal: true

# name: discourse-doc-categories
# about: TODO
# meta_topic_id: TODO
# version: 0.0.1
# authors: Discourse
# url: TODO
# required_version: 3.3.0.beta4-dev

enabled_site_setting :doc_categories_enabled

register_asset "stylesheets/common.scss"

GlobalSetting.add_default :docs_path, "docs"

module ::DocCategories
  PLUGIN_NAME = "discourse-doc-categories"

  CATEGORY_INDEX_TOPIC = "doc_category_index_topic"
end

require_relative "lib/doc_categories/engine"

after_initialize do
  register_category_custom_field_type(DocCategories::CATEGORY_INDEX_TOPIC, :integer)
  Site.preloaded_category_custom_fields << DocCategories::CATEGORY_INDEX_TOPIC

  # legacy docs
  add_to_serializer(
    :site,
    :docs_legacy_path,
    include_condition: -> { SiteSetting.doc_categories_docs_legacy_enabled },
  ) { GlobalSetting.docs_path }
end
