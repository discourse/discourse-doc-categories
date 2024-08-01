# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class InvalidateCacheOnEnabledSettingChange < Initializer
      def apply
        # invalidates the site cache when the plugin is turned on or off
        plugin.on_enabled_change { Site.clear_cache }
      end
    end
  end
end
