import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import icon from "discourse/helpers/d-icon";
import { resettableTracked } from "discourse/lib/tracked-tools";
import Topic from "discourse/models/topic";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";

export default class DocCategorySettings extends Component {
  static shouldRender(args, context) {
    return context.siteSettings.doc_categories_enabled;
  }

  @tracked indexTopic;
  @tracked loadingIndexTopic = !!this.indexTopicId;
  @resettableTracked indexTopicId = this.#effectiveTopicId();

  constructor() {
    super(...arguments);

    if (this.indexTopicId) {
      this.loadIndexTopic();
    }
  }

  #effectiveTopicId() {
    const id = this.args.outletArgs.category.doc_index_topic_id;
    return id > 0 ? id : null;
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
    if (!this.indexTopicId) {
      return;
    }

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
    this.category.doc_index_topic_id = topicId;
  }

  <template>
    <span {{didInsert this.loadIndexTopic}}></span>

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
            {{icon "xmark"}}
            {{this.errorMessage}}
          </div>
        {{/if}}
      </div>
    </section>
  </template>
}
