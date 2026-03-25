import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { service } from "@ember/service";
import { bind } from "discourse/lib/decorators";
import Topic from "discourse/models/topic";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";
import DocCategoryIndexEditor from "./doc-category-index-editor";

const MODE_TOPIC = "topic";
const MODE_DIRECT = "direct";

export default class DocCategoryIndexTab extends Component {
  @service dialog;

  @tracked mode = this.initialMode;
  @tracked indexTopic = null;
  @tracked loadingIndexTopic = !!this.indexTopicId;
  @tracked indexTopicContent = [];

  get category() {
    return this.args.category;
  }

  get indexTopicId() {
    return this.category?.doc_index_topic_id;
  }

  get initialMode() {
    if (this.category?.doc_index_topic_id) {
      return MODE_TOPIC;
    }
    return MODE_DIRECT;
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

  @action
  onChangeMode(event) {
    const newMode = event.target.value;
    if (
      newMode === MODE_TOPIC &&
      this.mode === MODE_DIRECT &&
      this.indexData?.length > 0
    ) {
      // Reset the select immediately (dialog is async)
      event.target.value = MODE_DIRECT;

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

    this.mode = newMode;

    if (newMode === MODE_DIRECT && this.category) {
      this.category.set("doc_index_topic_id", null);
    }
  }

  @action
  onChangeIndexTopic(topicId, topic) {
    this.indexTopic = topic;
    this.indexTopicContent = topic ? [topic] : [];

    if (this.category) {
      this.category.set("doc_index_topic_id", topicId);
    }
  }

  <template>
    <div class="doc-category-index-tab" {{didInsert this.loadIndexTopic}}>
      <h3>{{i18n "doc_categories.category_settings.title"}}</h3>

      <div class="doc-category-index-tab__mode-selector">
        <label>{{i18n
            "doc_categories.category_settings.index_editor.mode_label"
          }}</label>
        <select
          class="doc-category-index-tab__mode-dropdown"
          {{on "change" this.onChangeMode}}
        >
          <option value="direct" selected={{this.isDirectMode}}>
            {{i18n "doc_categories.category_settings.index_editor.mode_direct"}}
          </option>
          <option value="topic" selected={{this.isTopicMode}}>
            {{i18n "doc_categories.category_settings.index_editor.mode_topic"}}
          </option>
        </select>
      </div>

      {{#if this.isTopicMode}}
        <div class="doc-category-index-tab__topic-mode">
          <label>{{i18n
              "doc_categories.category_settings.index_topic.label"
            }}</label>
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
          @form={{@form}}
          @transientData={{@transientData}}
          @registerValidator={{@registerValidator}}
          @registerAfterReset={{@registerAfterReset}}
        />
      {{/if}}
    </div>
  </template>
}
