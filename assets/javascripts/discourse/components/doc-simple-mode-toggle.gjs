import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import bodyClass from "discourse/helpers/body-class";
import { and } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import isDocCategory, { DOC_ORIGINAL_STREAM } from "../lib/simple-mode";

export default class DocSimpleModeToggle extends Component {
  @service siteSettings;

  get commentsVisible() {
    const ps = this.postStream;
    return !!ps?.[DOC_ORIGINAL_STREAM] && ps.stream.length > 1;
  }

  get isSimpleMode() {
    return (
      this.siteSettings.doc_categories_simple_mode &&
      isDocCategory(this.topic?.category)
    );
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

  @action
  toggleComments() {
    if (this.commentsVisible) {
      this.#hideComments();
    } else {
      this.#showComments();
    }
  }

  #showComments() {
    const postStream = this.postStream;
    const originalStream = postStream?.[DOC_ORIGINAL_STREAM];
    if (!originalStream) {
      return;
    }

    postStream.stream.length = 0;
    postStream.stream.push(...originalStream);

    postStream.posts.length = 0;
    for (const id of originalStream) {
      const post = postStream.findLoadedPost(id);
      if (post) {
        postStream.posts.push(post);
      }
    }
  }

  #hideComments() {
    const postStream = this.postStream;
    if (!postStream || postStream.stream.length === 0) {
      return;
    }

    postStream.stream.length = 1;
    const op = postStream.posts.find((p) => p.post_number === 1);
    postStream.posts.length = 0;
    if (op) {
      postStream.posts.push(op);
    }
  }

  <template>
    {{#if (and this.isSimpleMode this.isFirstPost)}}
      {{bodyClass
        "doc-simple-mode"
        (unless this.commentsVisible "doc-simple-mode--collapsed")
      }}
      {{#if this.hasReplies}}
        <div class="doc-simple-mode-toggle">
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
