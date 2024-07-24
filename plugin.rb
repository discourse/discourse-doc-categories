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

  # index structure
  add_to_serializer(
    :basic_category,
    :doc_category_index,
    include_condition: -> do
      index_topic_id = object.custom_fields[::DocCategories::CATEGORY_INDEX_TOPIC]
      next false if index_topic_id.blank?

      index_topic = Topic.find_by(id: index_topic_id)
      next false if index_topic.blank?

      # ideally we should check if the current user has access to the topic above which would allow securely using
      # topics from any category, but we can't because the categories are serialized on the site serializer without a
      # guardian in scope.
      # as a workaround we force the topic category to match the category serialized, which implies the user has
      # access.
      # NOTICE THAT SUB-CATEGORIES ARE NOT CONSIDERED BECAUSE WE CAN'T CHECK THEIR PERMISSIONS
      next false unless object.id = index_topic.category_id

      first_post = index_topic.first_post
      next false if first_post.blank?

      @doc_category_index = DocCategories::DocIndexTopicParser.new(first_post.cooked).sections
      @doc_category_index.present?
    end,
  ) { @doc_category_index.as_json }

  # legacy docs
  add_to_serializer(
    :site,
    :docs_legacy_path,
    include_condition: -> { SiteSetting.doc_categories_docs_legacy_enabled },
  ) { GlobalSetting.docs_path }
end
