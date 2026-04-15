import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import DModal from "discourse/components/d-modal";
import { i18n } from "discourse-i18n";
import DocCategoryIndexEditor from "./doc-category-index-editor";

export default class DocIndexEditorModal extends Component {
  @tracked flash = null;
  @tracked footerElement = null;
  @tracked toolbarElement = null;

  @action
  registerFooterElement(element) {
    this.footerElement = element;
  }

  @action
  registerToolbarElement(element) {
    this.toolbarElement = element;
  }

  @action
  onApplyError(message) {
    this.flash = message;
  }

  <template>
    <DModal
      @title={{i18n
        "doc_categories.category_settings.index_editor.editor_modal_title"
      }}
      @closeModal={{@closeModal}}
      @flash={{this.flash}}
      @flashType="error"
      class="doc-index-editor-modal"
    >
      <:body>
        <div
          class="doc-index-editor-modal__toolbar-target"
          {{didInsert this.registerToolbarElement}}
        ></div>
        <DocCategoryIndexEditor
          @category={{@model.category}}
          @categoryId={{@model.category.id}}
          @indexData={{@model.indexData}}
          @form={{@model.form}}
          @transientData={{@model.transientData}}
          @toolbarElement={{this.toolbarElement}}
          @footerElement={{this.footerElement}}
          @onApplyError={{this.onApplyError}}
        />
      </:body>
      <:footer>
        <div
          class="doc-index-editor-modal__footer-target"
          {{didInsert this.registerFooterElement}}
        ></div>
      </:footer>
    </DModal>
  </template>
}
