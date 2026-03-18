import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import DButton from "discourse/components/d-button";
import { and } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import isDocCategory from "../lib/is-doc-category";
import normalizeSimpleModeTopicUrl from "../lib/normalize-simple-mode-topic-url";

const DEBUG_STORAGE_KEY = "doc-simple-mode-debug";

// Use a lazy require() to ensure we get the exact same module instance as core.
// Static imports from plugins can resolve to a different module copy, causing
// the cloakingPrevented Set to diverge from core's copy.
let _preventCloakingFn;
function preventCloaking(postId, prevent) {
  if (!_preventCloakingFn) {
    _preventCloakingFn = window.require(
      "discourse/modifiers/post-stream-viewport-tracker"
    ).preventCloaking;
  }
  _preventCloakingFn(postId, prevent);
}

export default class DocSimpleModeToggle extends Component {
  @service siteSettings;
  @service docSimpleModeState;

  @tracked loading = false;

  onInsert = modifier(() => {
    if (!this.commentsVisible) {
      // Defer to next frame so this runs after any viewport tracker destroy()
      // from a previous post-stream component, which clears the cloakingPrevented set.
      const id = requestAnimationFrame(() => this.#setCloakingPrevention(true));
      return () => cancelAnimationFrame(id);
    }
  });

  #setCloakingPrevention(prevent) {
    const posts = this.postStream?.posts;
    if (!posts) {
      return;
    }
    for (const post of posts) {
      if (post.post_number !== 1) {
        preventCloaking(post.id, prevent);
      }
    }
  }

  get #debugEnabled() {
    try {
      return window.localStorage.getItem(DEBUG_STORAGE_KEY) === "1";
    } catch {
      return false;
    }
  }

  get isSimpleMode() {
    return (
      this.siteSettings.doc_categories_simple_mode &&
      isDocCategory(this.topic?.category)
    );
  }

  get commentsVisible() {
    return this.docSimpleModeState.commentsVisible;
  }

  get replyCount() {
    return this.topic?.replyCount || 0;
  }

  get hasReplies() {
    return this.replyCount > 0;
  }

  get post() {
    return this.args.outletArgs.post;
  }

  get topic() {
    return this.post?.topic;
  }

  get isFirstPost() {
    return this.post?.post_number === 1;
  }

  get postStream() {
    return this.topic?.postStream;
  }

  async #loadAllPosts() {
    const stream = this.postStream;
    if (!stream) {
      return;
    }

    while (stream.canAppendMore) {
      await stream.appendMore();
    }
  }

  #logDebug(event, extra = {}) {
    if (!this.#debugEnabled) {
      return;
    }

    const bottomTopicMap = document.querySelector(".topic-map.--bottom");
    const topTopicMap = document.querySelector(".post__topic-map.--op");
    const replyPosts = [...document.querySelectorAll(".topic-post")].filter(
      (post) => post.dataset.postNumber !== "1"
    );
    const visibleReplyPosts = replyPosts.filter(
      (post) => window.getComputedStyle(post).display !== "none"
    );

    // eslint-disable-next-line no-console
    console.info("[doc-simple-mode]", {
      event,
      commentsVisible: this.commentsVisible,
      loading: this.loading,
      location: window.location.href,
      scrollY: window.scrollY,
      bodyClasses: document.body.className,
      mountedReplyPostNumbers: replyPosts.map(
        (post) => post.dataset.postNumber
      ),
      visibleReplyPostNumbers: visibleReplyPosts.map(
        (post) => post.dataset.postNumber
      ),
      bottomTopicMapDisplay: bottomTopicMap
        ? window.getComputedStyle(bottomTopicMap).display
        : null,
      topTopicMapDisplay: topTopicMap
        ? window.getComputedStyle(topTopicMap).display
        : null,
      ...extra,
    });
  }

  @action
  async toggleComments() {
    this.#logDebug("toggle-start");

    if (this.commentsVisible) {
      // Prevent cloaking BEFORE hiding so the cloaking system doesn't
      // cache 0-height values from display:none elements.
      this.#setCloakingPrevention(true);
      this.docSimpleModeState.hideComments();
      normalizeSimpleModeTopicUrl(this.topic?.url);
    } else {
      // Show comments FIRST so posts are CSS-visible, then load remaining.
      // This order is critical: the post-stream cloaking system measures
      // getBoundingClientRect() on posts. Posts must be visible when
      // appendMore() runs so cloaking caches correct dimensions.
      this.docSimpleModeState.showComments();
      this.#setCloakingPrevention(false);
      this.loading = true;
      this.#logDebug("load-start");
      try {
        await this.#loadAllPosts();
      } finally {
        this.loading = false;
        this.#logDebug("load-finish");
      }
    }

    this.#logDebug("toggle-finish", {
      nextCommentsVisible: this.commentsVisible,
    });
  }

  <template>
    {{#if (and this.isSimpleMode this.isFirstPost)}}
      {{#if this.hasReplies}}
        <div class="doc-simple-mode-toggle" {{this.onInsert}}>
          {{#if this.commentsVisible}}
            <DButton
              @action={{this.toggleComments}}
              @translatedLabel={{i18n
                "doc_categories.simple_mode.hide_comments"
              }}
              class="btn-default doc-simple-mode-toggle__button"
            />
          {{else}}
            <DButton
              @action={{this.toggleComments}}
              @isLoading={{this.loading}}
              @translatedLabel={{i18n
                "doc_categories.simple_mode.show_comments"
                count=this.replyCount
              }}
              class="btn-default doc-simple-mode-toggle__button"
            />
          {{/if}}
        </div>
      {{/if}}
    {{/if}}
  </template>
}
