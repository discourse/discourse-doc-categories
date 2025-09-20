import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";
import { isDocTopic } from "../../lib/is-doc-topic";

const BASE_CLASS = "doc-topic-comments";
const COLLAPSED_CLASS = "doc-topic-comments--collapsed";

export default class DocCommentsToggle extends Component {
  @tracked isCollapsed = false;
  topicId = null;

  @tracked _commentCount = 0;

  get commentCount() {
    return this._commentCount;
  }

  get hasComments() {
    return this._commentCount > 0;
  }

  get collapsed() {
    return this.isCollapsed;
  }

  get title() {
    return i18n("doc_categories.comments.title");
  }

  get summary() {
    return i18n("doc_categories.comments.collapsed_summary", {
      count: this.commentCount,
    });
  }

  get hint() {
    if (!this.hasComments) {
      return i18n("doc_categories.comments.none_hint");
    }

    return i18n(
      this.collapsed
        ? "doc_categories.comments.collapsed_hint"
        : "doc_categories.comments.expanded_hint"
    );
  }

  get toggleIcon() {
    return this.collapsed ? "chevron-down" : "chevron-up";
  }

  get ariaExpanded() {
    return this.collapsed ? "false" : "true";
  }

  get toggleLabelKey() {
    return this.collapsed
      ? "doc_categories.comments.expand"
      : "doc_categories.comments.collapse";
  }

  get docTopicEnabled() {
    return isDocTopic(this.args.model);
  }

  get isHidden() {
    return !this.hasComments;
  }

  @action
  toggleComments() {
    if (!this.hasComments) {
      return;
    }

    this.isCollapsed = !this.isCollapsed;
    this.#syncBodyClass();
  }

  @action
  handleInsert() {
    if (!this.docTopicEnabled) {
      return;
    }

    this.#applyTopicState({ topicChanged: true });
  }

  @action
  handleUpdate() {
    if (!this.docTopicEnabled) {
      this.#removeBodyClasses();
      return;
    }

    this.#applyTopicState();
  }

  @action
  handleDestroy() {
    this.#removeBodyClasses();
  }

  <template>
    {{#if this.docTopicEnabled}}
      <div
        class="doc-topic-comments-panel"
        data-topic-id={{@model.id}}
        hidden={{this.isHidden}}
        aria-hidden={{this.isHidden}}
        {{didInsert this.handleInsert}}
        {{didUpdate this.handleUpdate @model}}
        {{willDestroy this.handleDestroy}}
      >
        {{#if this.hasComments}}
          <div class="doc-topic-comments-panel__header">
            <span class="doc-topic-comments-panel__title">{{this.title}}</span>
            <span
              class="doc-topic-comments-panel__summary"
            >{{this.summary}}</span>
            <DButton
              @action={{this.toggleComments}}
              @label={{this.toggleLabelKey}}
              @icon={{this.toggleIcon}}
              @ariaLabel={{this.toggleLabelKey}}
              class="doc-topic-comments-panel__toggle btn-small"
              aria-expanded={{this.ariaExpanded}}
            />
          </div>

          <p class="doc-topic-comments-panel__hint">{{this.hint}}</p>
        {{/if}}
      </div>
    {{else}}
      <span {{willDestroy this.handleDestroy}}></span>
    {{/if}}
  </template>

  #applyTopicState({ topicChanged = false } = {}) {
    const topic = this.args.model;
    const nextTopicId = topic?.id ?? null;
    const nextCount = this.#computeCommentCount(topic);
    const hadComments = this._commentCount > 0;
    const topicActuallyChanged = topicChanged || nextTopicId !== this.topicId;

    this.topicId = nextTopicId;
    this._commentCount = nextCount;

    if (nextCount <= 0) {
      this.isCollapsed = false;
      this.#removeBodyClasses();
      return;
    }

    if (topicActuallyChanged || (!hadComments && nextCount > 0)) {
      this.isCollapsed = true;
    }

    this.#syncBodyClass();
  }

  #computeCommentCount(topic) {
    if (!topic) {
      return 0;
    }

    if (typeof topic.posts_count === "number") {
      return Math.max(topic.posts_count - 1, 0);
    }

    if (typeof topic.reply_count === "number") {
      return Math.max(topic.reply_count, 0);
    }

    const stream = topic.postStream?.stream;
    if (Array.isArray(stream)) {
      return Math.max(stream.length - 1, 0);
    }

    return 0;
  }

  #syncBodyClass() {
    if (!this.hasComments) {
      this.#removeBodyClasses();
      return;
    }

    this.#applyBaseClass();

    if (this.isCollapsed) {
      this.#applyCollapsedClass();
    } else {
      this.#removeCollapsedClass();
    }
  }

  #applyBaseClass() {
    if (typeof document === "undefined") {
      return;
    }

    document.body.classList.add(BASE_CLASS);
  }

  #applyCollapsedClass() {
    if (typeof document === "undefined") {
      return;
    }

    document.body.classList.add(COLLAPSED_CLASS);
  }

  #removeCollapsedClass() {
    if (typeof document === "undefined") {
      return;
    }

    document.body.classList.remove(COLLAPSED_CLASS);
  }

  #removeBodyClasses() {
    if (typeof document === "undefined") {
      return;
    }

    document.body.classList.remove(BASE_CLASS);
    document.body.classList.remove(COLLAPSED_CLASS);
  }
}
