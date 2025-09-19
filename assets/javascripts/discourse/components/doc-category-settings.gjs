import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import dIcon from "discourse/helpers/d-icon";
import Topic from "discourse/models/topic";
import { i18n } from "discourse-i18n";
import TopicChooser from "select-kit/components/topic-chooser";

export default class DocCategorySettings extends Component {
  static shouldRender(args, context) {
    return context.siteSettings.doc_categories_enabled;
  }

  @tracked
  indexTopicId = this.args.outletArgs.category.doc_index_topic_id;
  @tracked indexTopic;
  @tracked loadingIndexTopic = !!this.indexTopicId;

  constructor() {
    super(...arguments);

    if (this.indexTopicId) {
      this.loadIndexTopic();
    }
  }

  get category() {
    return this.args.outletArgs.category;
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

  get indexTopicContent() {
    if (this.loadingIndexTopic || !this.indexTopicId) {
      return [];
    }

    return [this.indexTopic];
  }

  get searchFilters() {
    return [
      "in:title",
      "include:unlisted",
      `category:${this.category.id}`,
    ].join(" ");
  }

  get shouldDisplayErrorMessage() {
    return !this.loadingIndexTopic && this.errorMessage;
  }

  async loadIndexTopic() {
    this.loadingIndexTopic = true;

    try {
      // using store.find doesn't work for topics
      const topic = await Topic.find(this.indexTopicId, {});
      this.onChangeIndexTopic(this.indexTopicId, topic);
    } finally {
      this.loadingIndexTopic = false;
    }
  }

  @action
  onChangeIndexTopic(topicId, topic) {
    this.indexTopic = topic;
    this.indexTopicId = topicId;
    this.category.set("doc_index_topic_id", topicId);
  }

  <template>
    <h3>{{i18n "doc_categories.category_settings.title"}}</h3>
    <section
      class="field doc-categories-settings doc-categories-settings__index-topic"
    >
      <label class="label">
        {{i18n "doc_categories.category_settings.index_topic.label"}}
      </label>
      <div class="controls">
        <TopicChooser
          @value={{this.indexTopicId}}
          @content={{this.indexTopicContent}}
          @onChange={{this.onChangeIndexTopic}}
          @options={{hash additionalFilters=this.searchFilters}}
        />
        {{#if this.shouldDisplayErrorMessage}}
          <div class="validation-error">
            {{dIcon "xmark"}}
            {{this.errorMessage}}
          </div>
        {{/if}}
      </div>
    </section>
  </template>
}
