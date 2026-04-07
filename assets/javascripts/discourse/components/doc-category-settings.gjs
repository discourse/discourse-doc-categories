import Component from "@glimmer/component";
import { cached } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";
import DocIndexModeState from "../lib/doc-index-mode-state";
import validateDocIndexSections from "../lib/doc-index-validation";
import DocIndexEditorModal from "./doc-index-editor-modal";
import DocIndexModeSelector from "./doc-index-mode-selector";

export default class DocCategorySettings extends Component {
  static shouldRender(args, context) {
    return (
      context.siteSettings.doc_categories_enabled &&
      !context.siteSettings.enable_simplified_category_creation
    );
  }

  @service dialog;
  @service modal;

  modeState = new DocIndexModeState({
    category: this.args.outletArgs.category,
    form: this.args.outletArgs.form,
    getTransientData: () => this.args.outletArgs.transientData,
    dialog: this.dialog,
    owner: this,
  });

  constructor() {
    super(...arguments);
    this.args.outletArgs.registerValidator?.(() => {
      if (!this.modeState.isDirectMode) {
        return;
      }

      const hasErrors = this.editorValidationErrors.length > 0;
      if (hasErrors) {
        this.dialog.alert(
          i18n(
            "doc_categories.category_settings.index_editor.save_validation_error"
          )
        );
      }

      return hasErrors;
    });
  }

  @cached
  get editorValidationErrors() {
    const sections = this.args.outletArgs.transientData?._docIndexSections;
    if (!sections?.length) {
      return [];
    }
    return validateDocIndexSections(sections);
  }

  @action
  openEditorModal() {
    this.modal.show(DocIndexEditorModal, {
      model: {
        category: this.modeState.category,
        indexData: this.modeState.indexData,
        form: this.args.outletArgs.form,
        transientData: this.args.outletArgs.transientData,
      },
    });
  }

  <template>
    <h3>{{i18n "doc_categories.category_settings.title"}}</h3>
    <section class="field doc-categories-settings">
      <div
        class="doc-categories-settings__mode-selector"
        {{didInsert this.modeState.loadIndexTopic}}
      >
        <DocIndexModeSelector
          @currentModeLabel={{this.modeState.currentModeLabel}}
          @onSwitchToNone={{this.modeState.switchToNoneMode}}
          @onSwitchToTopic={{this.modeState.switchToTopicMode}}
          @onSwitchToDirect={{this.modeState.switchToDirectMode}}
        />
      </div>

      {{#if this.modeState.isNoneMode}}
        <p class="doc-category-index-tab__none-help">
          {{i18n
            "doc_categories.category_settings.index_editor.none_mode_help"
          }}
        </p>
      {{else if this.modeState.isTopicMode}}
        <div class="doc-categories-settings__index-topic">
          <label class="label">
            {{i18n "doc_categories.category_settings.index_topic.label"}}
          </label>
          <div class="controls">
            <TopicChooser
              @value={{this.modeState.indexTopicId}}
              @content={{this.modeState.indexTopicContent}}
              @onChange={{this.modeState.onChangeIndexTopic}}
              @options={{hash additionalFilters=this.modeState.searchFilters}}
            />
            {{#if this.modeState.topicErrorMessage}}
              <div class="validation-error">
                {{icon "xmark"}}
                {{this.modeState.topicErrorMessage}}
              </div>
            {{/if}}
          </div>
        </div>
      {{else if this.modeState.isDirectMode}}
        <div class="doc-categories-settings__editor-trigger">
          <DButton
            @icon="pencil"
            @label="doc_categories.category_settings.index_editor.open_editor"
            @action={{this.openEditorModal}}
            class="btn-default"
          />
          {{#each this.editorValidationErrors as |error|}}
            <div class="doc-categories-settings__editor-errors">
              {{icon "xmark"}}
              {{error}}
            </div>
          {{/each}}
        </div>
      {{/if}}
    </section>
  </template>
}
