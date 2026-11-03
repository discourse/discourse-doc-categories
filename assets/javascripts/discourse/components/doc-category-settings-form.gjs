import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import Topic from "discourse/models/topic";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";

export default class DocCategorySettingsForm extends Component {
  static shouldRender(args, context) {
    return (
      context.siteSettings.doc_categories_enabled &&
      !context.siteSettings.doc_categories_index_editor
    );
  }

  #loadSequence = 0;

  @tracked _indexTopic = null;

  get #category() {
    return this.args.outletArgs.category;
  }

  get indexTopicId() {
    const value = this.args.outletArgs.transientData?.doc_index_topic_id;
    const id = value === undefined ? this.#category.doc_index_topic_id : value;
    return id > 0 ? Number(id) : null;
  }

  get indexTopicContent() {
    return this._indexTopic?.id === this.indexTopicId ? [this._indexTopic] : [];
  }

  get searchFilters() {
    return this.#category.id
      ? `in:title include:unlisted category:=${this.#category.id}`
      : "in:title include:unlisted";
  }

  @action
  async loadIndexTopic() {
    const id = this.indexTopicId;
    const sequence = ++this.#loadSequence;
    if (!id || this._indexTopic?.id === id) {
      return;
    }

    try {
      const topic = await Topic.find(id, {});
      if (!this.isDestroying && sequence === this.#loadSequence) {
        this._indexTopic = topic;
      }
    } catch {
      if (!this.isDestroying && sequence === this.#loadSequence) {
        this._indexTopic = null;
      }
    }
  }

  @action
  onChangeIndexTopic(field, topicId, topic) {
    this.#loadSequence++;
    this._indexTopic = topic || null;
    field.set(topicId ?? null);
  }

  <template>
    <div
      class="doc-categories-settings"
      {{didInsert this.loadIndexTopic}}
      {{didUpdate this.loadIndexTopic this.indexTopicId}}
    >
      <h3>{{i18n "doc_categories.category_settings.title"}}</h3>
      <@outletArgs.form.Field
        @format="large"
        @name="doc_index_topic_id"
        @title={{i18n "doc_categories.category_settings.index_topic.label"}}
        @type="custom"
        as |field|
      >
        <field.Control>
          <TopicChooser
            @content={{this.indexTopicContent}}
            @onChange={{fn this.onChangeIndexTopic field}}
            @options={{hash additionalFilters=this.searchFilters}}
            @value={{this.indexTopicId}}
          />
        </field.Control>
      </@outletArgs.form.Field>
    </div>
  </template>
}
