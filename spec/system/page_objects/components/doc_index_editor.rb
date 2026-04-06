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

      def has_success_toast?
        has_css?(".fk-d-toast.-success", wait: 5)
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

      def switch_to_general_tab
        find("li.edit-category-general a").click
        self
      end

      def switch_to_doc_index_tab
        find("li.edit-category-doc-index a").click
        self
      end
    end
  end
end
