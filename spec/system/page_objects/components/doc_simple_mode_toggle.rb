# frozen_string_literal: true

module PageObjects
  module Components
    class DocSimpleModeToggle < PageObjects::Components::Base
      TOGGLE_SELECTOR = ".doc-simple-mode-toggle__button"

      def click_toggle
        find(TOGGLE_SELECTOR).click
        self
      end

      def has_show_comments_button?(count:)
        has_css?(TOGGLE_SELECTOR, text: /Show #{count} comment/)
      end

      def has_hide_comments_button?
        has_css?(TOGGLE_SELECTOR, text: "Hide comments")
      end

      def has_no_toggle?
        has_no_css?(".doc-simple-mode-toggle")
      end
    end
  end
end
