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
          find(".doc-category-index-editor__section-title").fill_in(with: title)
          find(".doc-category-index-editor__confirm-title-btn").click
        end
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
        has_css?(".doc-category-index-editor__auto-indexed-badge")
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
    end
  end
end
