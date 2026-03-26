import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { trustHTML } from "@ember/template";
import DButton from "discourse/components/d-button";
import DropdownMenu from "discourse/components/dropdown-menu";
import DMenu from "discourse/float-kit/components/d-menu";
import icon from "discourse/helpers/d-icon";
import { bind } from "discourse/lib/decorators";
import Topic from "discourse/models/topic";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";
import DocCategoryIndexEditor from "./doc-category-index-editor";

const MODE_NONE = "none";
const MODE_TOPIC = "topic";
const MODE_DIRECT = "direct";

export default class DocCategoryIndexTab extends Component {
  @service dialog;

  @tracked mode = this.initialMode;
  @tracked indexTopic = null;
  @tracked loadingIndexTopic = !!this.indexTopicId;
  @tracked indexTopicContent = [];
  @tracked toolbarElement = null;
  _editorInstance = null;

  constructor() {
    super(...arguments);
    this.args.registerAfterReset(() => {
      this.mode = this.initialMode;
      this.indexTopic = null;
      this.indexTopicContent = [];

      if (this.indexTopicId) {
        this.loadIndexTopic();
      }
    });
  }

  get category() {
    return this.args.category;
  }

  get indexTopicId() {
    const id =
      this.args.transientData.doc_index_topic_id ??
      this.category.doc_index_topic_id;
    return id > 0 ? id : null;
  }

  get initialMode() {
    const topicId =
      this.args.transientData.doc_index_topic_id ??
      this.category.doc_index_topic_id;
    if (topicId != null && topicId > 0) {
      return MODE_TOPIC;
    }
    if (topicId === -1) {
      return MODE_DIRECT;
    }
    return MODE_NONE;
  }

  get isNoneMode() {
    return this.mode === MODE_NONE;
  }

  get isTopicMode() {
    return this.mode === MODE_TOPIC;
  }

  get isDirectMode() {
    return this.mode === MODE_DIRECT;
  }

  get indexData() {
    return this.category?.doc_category_index;
  }

  get searchFilters() {
    if (!this.category?.id) {
      return "in:title include:unlisted";
    }
    return `in:title include:unlisted category:${this.category.id}`;
  }

  get topicErrorMessage() {
    if (this.loadingIndexTopic) {
      return;
    }

    if (this.indexTopicId && !this.indexTopic) {
      return i18n(
        "doc_categories.category_settings.index_topic.errors.topic_not_found"
      );
    }

    if (
      this.indexTopic &&
      this.category &&
      this.indexTopic.category_id !== this.category.id
    ) {
      return i18n(
        "doc_categories.category_settings.index_topic.errors.mismatched-category",
        { category_name: this.indexTopic.category?.name }
      );
    }
  }

  @bind
  async loadIndexTopic() {
    if (!this.indexTopicId) {
      return;
    }

    this.loadingIndexTopic = true;
    try {
      const topic = await Topic.find(this.indexTopicId, {});
      this.indexTopic = topic;
      this.indexTopicContent = [topic];
    } finally {
      this.loadingIndexTopic = false;
    }
  }

  get currentModeLabel() {
    if (this.isTopicMode) {
      return i18n("doc_categories.category_settings.index_editor.mode_topic");
    } else if (this.isDirectMode) {
      return i18n("doc_categories.category_settings.index_editor.mode_direct");
    }
    return i18n("doc_categories.category_settings.index_editor.mode_none");
  }

  @action
  switchToNoneMode(dMenu) {
    dMenu.close();
    if (this.isNoneMode) {
      return;
    }
    this.mode = MODE_NONE;
    this.args.form.set("doc_index_topic_id", null);
    this.args.form.set("doc_index_sections", "[]");
  }

  @action
  switchToDirectMode(dMenu) {
    dMenu.close();
    if (this.isDirectMode) {
      return;
    }
    this.mode = MODE_DIRECT;
  }

  @action
  switchToTopicMode(dMenu) {
    dMenu.close();
    if (this.isTopicMode) {
      return;
    }
    if (this.indexData?.length > 0) {
      this.dialog.yesNoConfirm({
        message: i18n(
          "doc_categories.category_settings.index_editor.mode_switch_warning"
        ),
        didConfirm: () => {
          this.mode = MODE_TOPIC;
        },
      });
      return;
    }
    this.mode = MODE_TOPIC;
  }

  @action
  registerEditor(editor) {
    this._editorInstance = editor;
  }

  @action
  registerToolbarElement(element) {
    this.toolbarElement = element;
  }

  @action
  onChangeIndexTopic(topicId, topic) {
    this.indexTopic = topic;
    this.indexTopicContent = topic ? [topic] : [];
    this.args.form.set("doc_index_topic_id", topicId);
  }

  <template>
    <div class="doc-category-index-tab" {{didInsert this.loadIndexTopic}}>
      <div
        class="doc-category-index-tab__mode-selector"
        {{didInsert this.registerToolbarElement}}
      >
        <DMenu
          @identifier="doc-index-mode-selector"
          @triggerClass="btn-default doc-category-index-tab__mode-trigger"
        >
          <:trigger>
            <span>{{this.currentModeLabel}}</span>
            {{icon "angle-down"}}
          </:trigger>
          <:content as |dMenu|>
            <DropdownMenu as |dropdown|>
              <dropdown.item>
                <DButton
                  @action={{fn this.switchToDirectMode dMenu}}
                  class="--with-description doc-category-index-tab__mode-option"
                >
                  <div class="doc-category-index-tab__mode-option-texts">
                    <span
                      class="doc-category-index-tab__mode-option-label"
                    >{{i18n
                        "doc_categories.category_settings.index_editor.mode_direct"
                      }}</span>
                    <span
                      class="doc-category-index-tab__mode-option-description"
                    >{{i18n
                        "doc_categories.category_settings.index_editor.mode_direct_description"
                      }}</span>
                  </div>
                </DButton>
              </dropdown.item>
              <dropdown.item>
                <DButton
                  @action={{fn this.switchToTopicMode dMenu}}
                  class="--with-description doc-category-index-tab__mode-option"
                >
                  <div class="doc-category-index-tab__mode-option-texts">
                    <span
                      class="doc-category-index-tab__mode-option-label"
                    >{{i18n
                        "doc_categories.category_settings.index_editor.mode_topic"
                      }}</span>
                    <span
                      class="doc-category-index-tab__mode-option-description"
                    >{{i18n
                        "doc_categories.category_settings.index_editor.mode_topic_description"
                      }}</span>
                  </div>
                </DButton>
              </dropdown.item>
              <dropdown.item>
                <DButton
                  @action={{fn this.switchToNoneMode dMenu}}
                  class="--with-description doc-category-index-tab__mode-option"
                >
                  <div class="doc-category-index-tab__mode-option-texts">
                    <span
                      class="doc-category-index-tab__mode-option-label"
                    >{{i18n
                        "doc_categories.category_settings.index_editor.mode_none"
                      }}</span>
                    <span
                      class="doc-category-index-tab__mode-option-description"
                    >{{i18n
                        "doc_categories.category_settings.index_editor.mode_none_description"
                      }}</span>
                  </div>
                </DButton>
              </dropdown.item>
            </DropdownMenu>
          </:content>
        </DMenu>
      </div>

      {{#if this.isNoneMode}}
        <p class="doc-category-index-tab__none-help">
          {{i18n
            "doc_categories.category_settings.index_editor.none_mode_help"
          }}
        </p>
      {{else if this.isTopicMode}}
        <div class="doc-category-index-tab__topic-mode">
          <p class="doc-category-index-tab__topic-help">
            {{trustHTML
              (i18n
                "doc_categories.category_settings.index_editor.topic_mode_help"
              )
            }}
          </p>
          <TopicChooser
            @value={{this.indexTopicId}}
            @content={{this.indexTopicContent}}
            @onChange={{this.onChangeIndexTopic}}
            @options={{hash additionalFilters=this.searchFilters}}
          />
          {{#if this.topicErrorMessage}}
            <div class="doc-category-index-tab__error">
              {{this.topicErrorMessage}}
            </div>
          {{/if}}
        </div>
      {{/if}}

      {{#if this.isDirectMode}}
        <DocCategoryIndexEditor
          @category={{this.category}}
          @categoryId={{this.category.id}}
          @indexData={{this.indexData}}
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
