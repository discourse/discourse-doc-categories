# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class InvalidateCacheOnEnabledSettingChange < Initializer
      def apply
        # DiscourseEvent is used below intentionally because we want this code to work when the plugin is disabled
        # `plugin.on`, wouldn't
        DiscourseEvent.on(:site_setting_changed) do |name|
          # invalidates the site cache if the plugin is turned on or off
          Site.clear_cache if name == plugin.enabled_site_setting
        end
      end
    end
  end
end
