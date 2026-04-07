# frozen_string_literal: true

module PageObjects
  module Modals
    class DocIndexEditor < PageObjects::Modals::Base
      MODAL_SELECTOR = ".doc-index-editor-modal"

      def add_section(title:)
        footer.find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_section"),
        ).click

        within body.all(".doc-category-index-editor__section").last do
          find(".doc-category-index-editor__section-title").fill_in(with: title)
          find(".doc-category-index-editor__confirm-title-btn").click
        end
        self
      end

      def add_empty_section
        footer.find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_section"),
        ).click
        self
      end

      def add_manual_link(title:, url:)
        within body.all(".doc-category-index-editor__section").last do
          find(".d-combo-button-menu").click
        end
        find(
          "button",
          text: I18n.t("js.doc_categories.category_settings.index_editor.add_link"),
        ).click

        within body.all(".doc-category-index-editor__section").last do
          find(".doc-category-index-editor__link-title").fill_in(with: title)
          find(".doc-category-index-editor__link-url").fill_in(with: url)
          find(".doc-category-index-editor__confirm-edit-btn").click
        end
        self
      end

      def click_apply
        footer.find(".doc-category-index-editor__apply-btn").click
        self
      end

      def has_flash_error?
        has_css?("#{MODAL_SELECTOR} #modal-alert.alert-error")
      end

      def has_section_title?(title)
        body.has_css?(".doc-category-index-editor__section-title-label", text: title)
      end
    end
  end
end
