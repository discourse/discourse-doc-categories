import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { bind } from "discourse/lib/decorators";
import Topic from "discourse/models/topic";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";

export default class DocCategorySettingsForm extends Component {
  static shouldRender(args, context) {
    return context.siteSettings.doc_categories_enabled;
  }

  @tracked
  indexTopicId = this.args.outletArgs?.category?.doc_index_topic_id ?? null;
  @tracked indexTopic = null;
  @tracked loadingIndexTopic = !!this.indexTopicId;
  @tracked indexTopicContent = this.calculateIndexTopicContent();

  get category() {
    return this.args.outletArgs?.category;
  }

  get errorMessage() {
    if (this.loadingIndexTopic) {
      return;
    }

    if (this.indexTopicId && !this.indexTopic) {
      return i18n(
        "doc_categories.category_settings.index_topic.errors.topic_not_found"
      );
    } else if (
      this.indexTopic &&
      this.category &&
      this.indexTopic.category_id !== this.category.id
    ) {
      return i18n(
        "doc_categories.category_settings.index_topic.errors.mismatched-category",
        {
          category_name: this.indexTopic.category?.name,
        }
      );
    }
  }

  @bind
  calculateIndexTopicContent() {
    if (!this.indexTopicId || this.loadingIndexTopic || !this.indexTopic) {
      return [];
    }
    return [this.indexTopic];
  }

  get searchFilters() {
    if (!this.category?.id) {
      return "in:title include:unlisted";
    }
    return [
      "in:title",
      "include:unlisted",
      `category:${this.category.id}`,
    ].join(" ");
  }

  get shouldDisplayErrorMessage() {
    return !this.loadingIndexTopic && this.errorMessage;
  }

  @bind
  async loadIndexTopic() {
    if (!this.indexTopicId) {
      return;
    }

    this.loadingIndexTopic = true;

    try {
      const topic = await Topic.find(this.indexTopicId, {});
      this.loadingIndexTopic = false;
      this.#onChangeIndexTopic(this.indexTopicId, topic);
    } finally {
      this.loadingIndexTopic = false;
    }
  }

  @bind
  onChangeFormIndexTopic(field, topicId, topic) {
    this.#onChangeIndexTopic(topicId, topic);
    field.set(topicId);
  }

  #onChangeIndexTopic(topicId, topic) {
    this.indexTopicId = topicId;
    this.indexTopic = topic;
    this.loadingIndexTopic = false;
    this.indexTopicContent = this.calculateIndexTopicContent();
  }

  <template>
    <h3 {{didInsert this.loadIndexTopic}}>
      {{i18n "doc_categories.category_settings.title"}}
    </h3>
    <@outletArgs.form.Field
      @name="doc_index_topic_id"
      @title={{i18n "doc_categories.category_settings.index_topic.label"}}
      @format="large"
      as |field|
    >
      <field.Custom>
        <TopicChooser
          @value={{this.indexTopicId}}
          @content={{this.indexTopicContent}}
          @onChange={{fn this.onChangeFormIndexTopic field}}
          @options={{hash additionalFilters=this.searchFilters}}
        />
      </field.Custom>
    </@outletArgs.form.Field>
  </template>
}
