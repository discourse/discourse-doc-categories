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

register_svg_icon "far-file"

module ::DocCategories
  PLUGIN_NAME = "discourse-doc-categories"

  CATEGORY_INDEX_TOPIC = "doc_category_index_topic"

  def self.legacyMode?
    # disable the compatibility mode if the docs plugin is enabled
    return false if defined?(::Docs) && SiteSetting.docs_enabled
    SiteSetting.doc_categories_docs_legacy_enabled
  end

  class Initializer
    attr_reader :plugin

    def initialize(plugin)
      @plugin = plugin
    end

    def apply
      # this method should be overridden by subclasses
      raise NotImplementedError
    end
  end

  module Initializers
    module_function

    def apply(plugin)
      constants.each do |c|
        klass = const_get(c)
        klass.new(plugin).apply if klass.is_a?(Class) && klass < Initializer
      end
    end
  end
end

require_relative "lib/doc_categories/engine"

after_initialize do
  register_category_custom_field_type(DocCategories::CATEGORY_INDEX_TOPIC, :integer)
  Site.preloaded_category_custom_fields << DocCategories::CATEGORY_INDEX_TOPIC

  # legacy docs
  add_to_serializer(
    :site,
    :docs_legacy_path,
    include_condition: -> { DocCategories.legacyMode? },
  ) { GlobalSetting.docs_path }

  DocCategories::Initializers.apply(self)

  # this plugin uses a plugin initializer pattern to (hopefully) better organize plugin API calls
  # instead of having them all in one file.
  #
  # PLEASE add the plugin code into a separate file in the lib/doc_categories/initializers folder, where
  # they can be organized by theme or feature.
  #
  # To create the plugin initializer file, you should follow the pattern below:
  #
  # module ::DocCategories
  #   module Initializers
  #     class SampleInitializer < Initializer
  #       def apply
  #         # use plugin.add_to_class, plugin.add_to_serializer, etc. here
  #         # eg. plugin.add_to_serializer(...)
  #       end
  #     end
  #   end
  # end
end
