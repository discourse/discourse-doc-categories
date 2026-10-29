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
import docIndexSaveLock from "../modifiers/doc-index-save-lock";
import DocCategoryIndexEditor from "./doc-category-index-editor";
import DocIndexModeSelector from "./doc-index-mode-selector";

const INDEX_FIELDS = [
  "doc_index_topic_id",
  "doc_index_sections",
  "_docIndexEditorState",
  "_docIndexAutoIndexIncludeSubcategories",
];

export default class DocCategoryIndexTab extends Component {
  @service dialog;
  @service docIndexSaveLock;
  @service router;
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
  #savedFormValues;
  #removeIndexError;
  #discarding = false;
  #confirmingNavigation = false;

  constructor() {
    super(...arguments);
    this.captureSavedFormValues();
    this.router.on("routeWillChange", this.checkUnsavedIndex);
    this.args.registerValidator((data, { addError, removeError } = {}) => {
      if (this.isDestroying || this.isDestroyed || this.#discarding) {
        return;
      }
      this.#removeIndexError = () => removeError?.("doc_index_sections");
      this.#removeIndexError();

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
      if (!this.isDestroying && !this.isDestroyed) {
        this.modeState.reset();
      }
    });
  }

  willDestroy() {
    super.willDestroy();
    this.router.off("routeWillChange", this.checkUnsavedIndex);
  }

  @action
  captureSavedFormValues(indexStructure) {
    if (indexStructure !== undefined) {
      this.args.category.set("doc_category_index", indexStructure);
    }
    this.#savedFormValues = Object.fromEntries(
      INDEX_FIELDS.map((name) => [name, this.args.transientData?.[name]])
    );
  }

  @action
  checkUnsavedIndex(transition) {
    if (transition.isAborted) {
      return;
    }
    if (this.docIndexSaveLock.isSaving) {
      transition.abort();
      return;
    }
    if (this.#discarding) {
      return;
    }
    const from = transition.from;
    const to = transition.to;
    if (
      !from?.name?.startsWith("editCategory.tabs") ||
      from.params.tab !== "doc-index" ||
      (to?.name === from.name &&
        to.params.tab === "doc-index" &&
        JSON.stringify(to.parent?.params) ===
          JSON.stringify(from.parent?.params))
    ) {
      return;
    }
    const changed = INDEX_FIELDS.some(
      (name) =>
        JSON.stringify(this.args.transientData?.[name]) !==
        JSON.stringify(this.#savedFormValues[name])
    );
    if (!changed && !this.#editorInstance?.editingCount) {
      return;
    }

    transition.abort();
    if (this.#confirmingNavigation) {
      return;
    }
    this.#confirmingNavigation = true;
    this.dialog.confirm({
      message: i18n(
        "doc_categories.category_settings.index_editor.unsaved_navigation"
      ),
      confirmButtonLabel:
        "doc_categories.category_settings.index_editor.discard_and_leave",
      cancelButtonLabel: "doc_categories.category_settings.index_editor.stay",
      didCancel: () => {
        this.#confirmingNavigation = false;
      },
      didConfirm: () => {
        this.#discarding = true;
        for (const name of INDEX_FIELDS) {
          this.args.form.set(name, this.#savedFormValues[name]);
          this.args.form.commitField(name);
        }
        this.#removeIndexError?.();
        transition.retry();
      },
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
    <fieldset
      class="doc-category-index-tab"
      disabled={{this.docIndexSaveLock.isSaving}}
      {{docIndexSaveLock this.docIndexSaveLock.isSaving}}
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
          {{#if this.modeState.inheritedIndexCategory}}
            {{i18n
              "doc_categories.category_settings.index_editor.inherited_mode_help"
              category_name=this.modeState.inheritedIndexCategory.name
            }}
          {{else}}
            {{i18n
              "doc_categories.category_settings.index_editor.none_mode_help"
            }}
          {{/if}}
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
          @onApplied={{this.captureSavedFormValues}}
          @registerAfterReset={{@registerAfterReset}}
        />
      {{/if}}
    </fieldset>
  </template>
}
