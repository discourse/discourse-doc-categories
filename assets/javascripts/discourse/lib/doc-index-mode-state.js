import { tracked } from "@glimmer/tracking";
import { bind } from "discourse/lib/decorators";
import Topic from "discourse/models/topic";
import { i18n } from "discourse-i18n";

const MODE_NONE = "none";
const MODE_TOPIC = "topic";
const MODE_DIRECT = "direct";

/**
 * Shared state manager for the doc index mode selector, used by both the
 * new-flow tab (DocCategoryIndexTab) and the legacy-flow settings
 * (DocCategorySettings). Encapsulates mode tracking, mode switching with
 * confirmation dialogs, topic loading, and topic validation.
 */
export default class DocIndexModeState {
  @tracked mode;
  @tracked indexTopic = null;
  @tracked loadingIndexTopic;
  @tracked indexTopicContent = [];

  #category;
  #form;
  #getTransientData;
  #dialog;
  #owner;

  constructor({ category, form, getTransientData, dialog, owner }) {
    this.#category = category;
    this.#form = form;
    this.#getTransientData = getTransientData;
    this.#dialog = dialog;
    this.#owner = owner;
    this.mode = this.initialMode;
    this.loadingIndexTopic = !!this.indexTopicId;
  }

  get category() {
    return this.#category;
  }

  get initialMode() {
    const topicId =
      this.#getTransientData()?.doc_index_topic_id ??
      this.#category.doc_index_topic_id;
    if (topicId != null && topicId > 0) {
      return MODE_TOPIC;
    }
    if (topicId === -1) {
      return MODE_DIRECT;
    }
    return MODE_NONE;
  }

  get indexTopicId() {
    const id =
      this.#getTransientData()?.doc_index_topic_id ??
      this.#category.doc_index_topic_id;
    return id > 0 ? id : null;
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
    return this.#category.doc_category_index;
  }

  get currentModeLabel() {
    if (this.isTopicMode) {
      return i18n("doc_categories.category_settings.index_editor.mode_topic");
    } else if (this.isDirectMode) {
      return i18n("doc_categories.category_settings.index_editor.mode_direct");
    }
    return i18n("doc_categories.category_settings.index_editor.mode_none");
  }

  get searchFilters() {
    if (!this.#category.id) {
      return "in:title include:unlisted";
    }
    return `in:title include:unlisted category:=${this.#category.id}`;
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

    if (this.indexTopic && this.indexTopic.category_id !== this.#category.id) {
      return i18n(
        "doc_categories.category_settings.index_topic.errors.mismatched_category",
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
      if (this.#owner?.isDestroying || this.#owner?.isDestroyed) {
        return;
      }
      this.indexTopic = topic;
      this.indexTopicContent = [topic];
    } finally {
      if (!this.#owner?.isDestroying && !this.#owner?.isDestroyed) {
        this.loadingIndexTopic = false;
      }
    }
  }

  @bind
  switchToNoneMode(dMenu) {
    dMenu.close();
    if (this.isNoneMode) {
      return;
    }

    const hasData = this.indexTopicId || this.indexData?.length > 0;
    if (hasData) {
      this.#dialog.yesNoConfirm({
        message: i18n(
          "doc_categories.category_settings.index_editor.disable_confirm"
        ),
        didConfirm: () => this.#applyNoneMode(),
      });
      return;
    }

    this.#applyNoneMode();
  }

  #applyNoneMode() {
    this.mode = MODE_NONE;
    this.#form.set("doc_index_topic_id", null);
    this.#form.set("doc_index_sections", "[]");
  }

  @bind
  switchToDirectMode(dMenu) {
    dMenu.close();
    if (this.isDirectMode) {
      return;
    }
    if (this.isTopicMode && this.indexTopicId) {
      this.#dialog.yesNoConfirm({
        message: i18n(
          "doc_categories.category_settings.index_editor.switch_to_direct_warning"
        ),
        didConfirm: () => {
          this.mode = MODE_DIRECT;
          this.#form.set("doc_index_topic_id", -1);
        },
      });
      return;
    }
    this.mode = MODE_DIRECT;
    this.#form.set("doc_index_topic_id", -1);
  }

  @bind
  switchToTopicMode(dMenu) {
    dMenu.close();
    if (this.isTopicMode) {
      return;
    }
    if (this.indexData?.length > 0) {
      this.#dialog.yesNoConfirm({
        message: i18n(
          "doc_categories.category_settings.index_editor.mode_switch_warning"
        ),
        didConfirm: () => this.#applyTopicMode(),
      });
      return;
    }
    this.#applyTopicMode();
  }

  #applyTopicMode() {
    this.mode = MODE_TOPIC;
    this.#form.set("doc_index_topic_id", null);
    this.#form.set("doc_index_sections", null);
  }

  @bind
  onChangeIndexTopic(topicId, topic) {
    this.indexTopic = topic;
    this.indexTopicContent = topic ? [topic] : [];
    this.#form.set("doc_index_topic_id", topicId);
  }

  reset() {
    this.mode = this.initialMode;
    this.indexTopic = null;
    this.indexTopicContent = [];

    if (this.indexTopicId) {
      this.loadIndexTopic();
    }
  }
}
