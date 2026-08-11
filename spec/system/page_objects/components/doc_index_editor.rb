# frozen_string_literal: true

module PageObjects
  module Components
    class DocIndexEditor < PageObjects::Components::Base
      def visit_doc_index_tab(category)
        page.visit("/c/#{category.slug}/edit/doc-index")
        has_css?(".doc-category-index-tab")
        self
      end

      def switch_to_mode(mode_key)
        find(".doc-category-index-tab__mode-selector .fk-d-menu__trigger").click
        find(
          ".doc-category-index-tab__mode-option-label",
          text: I18n.t("js.doc_categories.category_settings.index_editor.#{mode_key}"),
        ).click
        self
      end

      def open_mode_selector
        find(".doc-category-index-tab__mode-selector .fk-d-menu__trigger").click
        self
      end

      def has_mode_option?(mode_key)
        has_css?(
          ".doc-category-index-tab__mode-option-label",
          text: I18n.t("js.doc_categories.category_settings.index_editor.#{mode_key}"),
        )
      end

      def has_no_mode_option?(mode_key)
        has_no_css?(
          ".doc-category-index-tab__mode-option-label",
          text: I18n.t("js.doc_categories.category_settings.index_editor.#{mode_key}"),
        )
      end

      def has_editor?
        has_css?(".doc-category-index-editor")
      end

      def has_no_editor?
        has_no_css?(".doc-category-index-editor")
      end

      def has_none_help?
        has_css?(".doc-category-index-tab__none-help")
      end

      def has_topic_mode?
        has_css?(".doc-category-index-tab__topic-mode")
      end

      def add_section(title:)
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_section"),
        ).click

        within all(".doc-category-index-editor__section").last do
          # The first section does not auto-enter edit mode and later ones do, so
          # wait for whichever of the two states arrived and then branch without
          # waiting again. Asking for the absence of one instead waits out the
          # full duration whenever it is present, which the suite treats as a
          # failure in its own right.
          has_css?(
            ".doc-category-index-editor__section-title, .doc-category-index-editor__edit-btn",
          )
          find(".doc-category-index-editor__edit-btn").click if has_css?(
            ".doc-category-index-editor__edit-btn",
            wait: 0,
          )
          find(".doc-category-index-editor__section-title").fill_in(with: title)
          find(".doc-category-index-editor__confirm-title-btn").click
        end
        self
      end

      def add_section_without_title
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_section"),
        ).click
        self
      end

      def has_section_title_editing?
        has_css?("input.doc-category-index-editor__section-title")
      end

      def has_no_section_title_editing?
        has_no_css?("input.doc-category-index-editor__section-title")
      end

      def has_first_section_placeholder?
        has_css?(
          ".doc-category-index-editor__section-title-label.--placeholder",
          text: I18n.t("js.doc_categories.category_settings.index_editor.first_section_no_title"),
        )
      end

      def click_cancel_title_edit
        find(".doc-category-index-editor__cancel-title-btn").click
        self
      end

      def add_manual_link(title:, url:)
        within all(".doc-category-index-editor__section").last do
          find(".d-combo-button-menu").click
        end
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_link"),
        ).click

        within all(".doc-category-index-editor__section").last do
          find(".doc-category-index-editor__link-title").fill_in(with: title)
          find(".doc-category-index-editor__link-url").fill_in(with: url)
          find(".doc-category-index-editor__confirm-edit-btn").click
        end
        self
      end

      def click_apply
        find(".doc-category-index-editor__apply-btn").click
        self
      end

      def has_apply_disabled?
        has_css?(".doc-category-index-editor__apply-btn[disabled]")
      end

      def has_no_apply_disabled?
        has_no_css?(".doc-category-index-editor__apply-btn[disabled]")
      end

      def has_section_validation_error?
        has_css?(".doc-category-index-editor__validation-error")
      end

      def has_no_section_validation_error?
        has_no_css?(".doc-category-index-editor__validation-error")
      end

      def has_applied?
        has_button?(
          I18n.t("js.doc_categories.category_settings.index_editor.applied"),
          disabled: true,
          wait: 5,
        )
      end

      def save_category
        find(".admin-changes-banner .btn-primary").click
        self
      end

      def has_pending_changes?
        has_css?(".admin-changes-banner")
      end

      def has_no_pending_changes?
        has_no_css?(".admin-changes-banner")
      end

      def has_save_banner?
        has_css?(".admin-changes-banner .btn-primary")
      end

      def select_index_topic(topic)
        find(".topic-chooser .select-kit-header").click
        has_css?(".topic-chooser .filter-input")
        find(".topic-chooser .filter-input").fill_in(with: topic.id.to_s)
        find(".topic-chooser .topic-row", text: topic.title).click
        self
      end

      def has_selected_topic?(topic)
        has_css?(".topic-chooser .select-kit-header .selected-name .name", text: topic.title)
      end

      def has_section_title?(title)
        has_css?(".doc-category-index-editor__section-title-label", text: title)
      end

      def add_auto_index_section
        find(".doc-category-index-editor__footer .d-combo-button-menu").click
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_auto_index_section"),
        ).click
        self
      end

      def has_auto_index_section?
        has_css?(".doc-category-index-editor__auto-index-badge")
      end

      def has_no_auto_index_section?
        has_no_css?(".doc-category-index-editor__auto-index-badge")
      end

      def has_auto_index_placeholder?
        has_css?(".doc-category-index-editor__link-card.--ghost")
      end

      def has_no_auto_index_button?
        has_no_button?(
          I18n.t("js.doc_categories.category_settings.index_editor.add_auto_index_section"),
        )
      end

      def has_auto_indexed_link_badge?
        has_css?(".doc-category-index-editor__item-badge")
      end

      def click_auto_index_badge
        find(".doc-category-index-editor__auto-index-badge").click
        self
      end

      def toggle_include_subcategories
        click_auto_index_badge
        find(".doc-category-index-editor__auto-index-subcategories input[type='checkbox']").click
        self
      end

      def click_resync_button
        click_auto_index_badge
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.resync_auto_index"),
        ).click
        self
      end

      def has_auto_index_badge_with_text?(text)
        has_css?(".doc-category-index-editor__auto-index-badge", text: text)
      end

      def section_count
        all(".doc-category-index-editor__section").count
      end

      def switch_to_general_tab
        find("li.edit-category-general a").click
        self
      end

      def switch_to_doc_index_tab
        find("li.edit-category-doc-index a").click
        self
      end

      # Legacy flow helpers

      def visit_category_settings(category)
        page.visit("/c/#{category.slug}/edit/settings")
        has_css?(".doc-categories-settings")
        self
      end

      def has_legacy_mode_dropdown?
        has_css?(".doc-categories-settings__mode-selector .fk-d-menu__trigger")
      end

      def switch_legacy_mode(mode_key)
        find(".doc-categories-settings__mode-selector .fk-d-menu__trigger").click
        find(
          ".doc-category-index-tab__mode-option-label",
          text: I18n.t("js.doc_categories.category_settings.index_editor.#{mode_key}"),
        ).click
        self
      end

      def click_open_editor
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.open_editor"),
        ).click
        self
      end

      def has_editor_validation_errors?
        has_css?(".doc-categories-settings__editor-errors")
      end

      def has_no_editor_validation_errors?
        has_no_css?(".doc-categories-settings__editor-errors")
      end

      def has_legacy_topic_mode?
        has_css?(".doc-categories-settings__index-topic")
      end

      def has_legacy_editor_trigger?
        has_css?(".doc-categories-settings__editor-trigger")
      end

      def save_legacy_category
        find("#save-category").click
        self
      end

      # The arrows are the keyboard path beside the drag. Found by their
      # accessible name rather than by position, since that name is the contract
      # a screen reader user navigates by, and an index is what a reorder moves.
      def move_link(title, direction)
        find("button[title='#{move_link_label(title, direction)}']").click
        self
      end

      def move_section(title, direction)
        find("button[title='#{move_section_label(title, direction)}']").click
        self
      end

      def has_link_move_disabled?(title, direction)
        has_css?("button[title='#{move_link_label(title, direction)}'][aria-disabled='true']")
      end

      def has_link_move_available?(title, direction)
        has_no_css?("button[title='#{move_link_label(title, direction)}'][aria-disabled='true']")
      end

      # A move that crosses a section boundary destroys the row and builds a new
      # one, so keeping focus on the pressed arrow is the editor's job rather
      # than the button pair's.
      def has_focused_move_button?(title, direction)
        has_css?("button[title='#{move_link_label(title, direction)}']:focus")
      end

      def move_link_label(title, direction)
        I18n.t(
          "js.doc_categories.category_settings.index_editor.move_link_#{direction}",
          label: title,
        )
      end

      def move_section_label(title, direction)
        I18n.t(
          "js.doc_categories.category_settings.index_editor.move_section_#{direction}",
          label: title,
        )
      end

      # Link titles in render order, which is the only thing a reorder changes
      # and so the only thing worth measuring one against.
      def link_labels
        all(".doc-category-index-editor__link-label").map(&:text)
      end

      def section_labels
        all(".doc-category-index-editor__section-title-label").map(&:text)
      end

      def links_in_section(title)
        all(".doc-category-index-editor__section")
          .find { |section| section.text.include?(title) }
          .all(".doc-category-index-editor__link-label", minimum: 0)
          .map(&:text)
      end

      # Retrying matchers rather than a bare comparison against `link_labels`:
      # `drag_and_drop` drives the browser directly and so skips Capybara's
      # settle, meaning an order read straight after a drop can still be the
      # order from before it.
      def has_link_order?(titles)
        has_css?(".doc-category-index-editor__link-label", count: titles.size) &&
          link_labels == titles
      end

      def has_section_order?(titles)
        has_css?(".doc-category-index-editor__section-title-label", count: titles.size) &&
          section_labels == titles
      end
    end
  end
end
