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

  class PluginInitializer
    attr_reader :plugin

    def initialize(plugin)
      @plugin = plugin
    end

    def apply
      # this method should be overridden by subclasses
      raise NotImplementedError
    end
  end

  module PluginInitializers
    module_function

    def apply(plugin)
      constants.each do |c|
        klass = const_get(c)

        klass.new(plugin).apply if klass.is_a?(Class) && klass < PluginInitializer
      end
    end
  end
end

require_relative "lib/doc_categories/engine"

after_initialize do
  register_category_custom_field_type(DocCategories::CATEGORY_INDEX_TOPIC, :integer)
  Site.preloaded_category_custom_fields << DocCategories::CATEGORY_INDEX_TOPIC

  add_to_class(:category, :doc_index_topic_id) do
    custom_fields[DocCategories::CATEGORY_INDEX_TOPIC]
  end

  # legacy docs
  add_to_serializer(
    :site,
    :docs_legacy_path,
    include_condition: -> { SiteSetting.doc_categories_docs_legacy_enabled },
  ) { GlobalSetting.docs_path }

  DocCategories::PluginInitializers.apply(self)

  # this plugin uses a plugin initializer pattern to (hopefully) better organize plugin API calls
  # instead of having them all in one file.
  #
  # PLEASE add the plugin code into a separate file in the lib/doc_categories/plugin_initializers folder, where
  # they can be organized by theme or feature.
  #
  # To create the plugin initializer file, you should follow the pattern below:
  #
  # module ::DocCategories
  #   module PluginInitializers
  #     class SampleInitializer < PluginInitializer
  #       def apply
  #         # use plugin.add_to_class, plugin.add_to_serializer, etc. here
  #         # eg. plugin.add_to_serializer(...)
  #       end
  #     end
  #   end
  # end
end
