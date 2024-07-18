import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { action } from "@ember/object";
import Topic from "discourse/models/topic";
import i18n from "discourse-common/helpers/i18n";
import TopicChooser from "select-kit/components/topic-chooser";

export default class DocCategorySettings extends Component {
  static shouldRender(args, context) {
    return context.siteSettings.doc_categories_enabled;
  }

  @tracked
  indexTopicId =
    this.args.outletArgs.category.custom_fields.doc_category_index_topic;
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

  get indexTopicContent() {
    if (this.loadingIndexTopic || !this.indexTopicId) {
      return [];
    }

    return [this.indexTopic];
  }

  async loadIndexTopic() {
    this.loadingIndexTopic = true;

    try {
      // using store.find doesn't work for topics
      this.indexTopic = await Topic.find(this.indexTopicId, {});
    } finally {
      this.loadingIndexTopic = false;
    }
  }

  @action
  onChangeIndexTopic(topicId, topic) {
    this.indexTopic = topic;
    this.indexTopicId = topicId;
    this.category.custom_fields.doc_category_index_topic = topicId;
  }

  <template>
    <h3>{{i18n "doc_categories.category_settings.title"}}</h3>
    <section class="field">
      <label class="checkbox-label">
        {{i18n "doc_categories.category_settings.index_topic"}}
      </label>
      <div class="controls">
        <TopicChooser
          @value={{this.indexTopicId}}
          @content={{this.indexTopicContent}}
          @onChange={{this.onChangeIndexTopic}}
          @options={{hash additionalFilters="in:title include:unlisted"}}
        />
      </div>
    </section>
  </template>
}
