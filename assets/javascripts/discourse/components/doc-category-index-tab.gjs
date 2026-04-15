import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";
import DocIndexModeState from "../lib/doc-index-mode-state";
import DocCategoryIndexEditor from "./doc-category-index-editor";
import DocIndexModeSelector from "./doc-index-mode-selector";

export default class DocCategoryIndexTab extends Component {
  @service dialog;
  @service siteSettings;

  @tracked toolbarElement = null;
  modeState = new DocIndexModeState({
    category: this.args.category,
    form: this.args.form,
    getTransientData: () => this.args.transientData,
    dialog: this.dialog,
    owner: this,
  });
  #editorInstance = null;

  constructor() {
    super(...arguments);
    this.args.registerValidator((data, { addError, removeError } = {}) => {
      removeError?.("doc_index_sections");

      if (!this.modeState.isDirectMode || !this.#editorInstance) {
        return;
      }

      const errors = this.#editorInstance.validationErrors;
      if (errors.length > 0 && addError) {
        addError("doc_index_sections", {
          title: i18n(
            "doc_categories.category_settings.index_editor.mode_direct"
          ),
          message: errors.join(" "),
        });
      }

      return errors.length > 0;
    });
    this.args.registerAfterReset(() => {
      this.modeState.reset();
    });
  }

  @action
  registerEditor(editor) {
    this.#editorInstance = editor;
  }

  get showEditorOption() {
    return (
      this.siteSettings.doc_categories_index_editor ||
      this.modeState.isDirectMode
    );
  }

  @action
  registerToolbarElement(element) {
    this.toolbarElement = element;
  }

  <template>
    <div
      class="doc-category-index-tab"
      {{didInsert this.modeState.loadIndexTopic}}
    >
      <div class="doc-category-index-tab__header">
        <div class="doc-category-index-tab__mode-selector">
          <DocIndexModeSelector
            @currentModeLabel={{this.modeState.currentModeLabel}}
            @showEditorOption={{this.showEditorOption}}
            @onSwitchToNone={{this.modeState.switchToNoneMode}}
            @onSwitchToTopic={{this.modeState.switchToTopicMode}}
            @onSwitchToDirect={{this.modeState.switchToDirectMode}}
          />
        </div>
        <div
          class="doc-category-index-tab__toolbar"
          {{didInsert this.registerToolbarElement}}
        ></div>
      </div>

      {{#if this.modeState.isNoneMode}}
        <p class="doc-category-index-tab__none-help">
          {{i18n
            "doc_categories.category_settings.index_editor.none_mode_help"
          }}
        </p>
      {{else if this.modeState.isTopicMode}}
        <div class="doc-category-index-tab__topic-mode">
          <p class="doc-category-index-tab__topic-help">
            {{trustHTML
              (i18n
                "doc_categories.category_settings.index_editor.topic_mode_help"
              )
            }}
          </p>
          <TopicChooser
            @value={{this.modeState.indexTopicId}}
            @content={{this.modeState.indexTopicContent}}
            @onChange={{this.modeState.onChangeIndexTopic}}
            @options={{hash additionalFilters=this.modeState.searchFilters}}
          />
          {{#if this.modeState.topicErrorMessage}}
            <div class="doc-category-index-tab__error">
              {{this.modeState.topicErrorMessage}}
            </div>
          {{/if}}
        </div>
      {{/if}}

      {{#if this.modeState.isDirectMode}}
        <DocCategoryIndexEditor
          @category={{this.modeState.category}}
          @categoryId={{this.modeState.category.id}}
          @indexData={{this.modeState.indexData}}
          @toolbarElement={{this.toolbarElement}}
          @form={{@form}}
          @transientData={{@transientData}}
          @onRegisterEditor={{this.registerEditor}}
          @registerAfterReset={{@registerAfterReset}}
        />
      {{/if}}
    </div>
  </template>
}
