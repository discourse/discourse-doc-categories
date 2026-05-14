import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import bodyClass from "discourse/helpers/body-class";
import { and } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import {
  collapseStream,
  expandStream,
  getState,
  inDocSimpleMode,
} from "../lib/simple-mode";

export default class DocSimpleModeToggle extends Component {
  @service siteSettings;

  get post() {
    return this.args.outletArgs.post;
  }

  get topic() {
    return this.post?.topic;
  }

  get postStream() {
    return this.topic?.postStream;
  }

  get isSimpleMode() {
    return inDocSimpleMode(this.siteSettings, this.topic?.category);
  }

  get isFirstPost() {
    return this.post?.post_number === 1;
  }

  get commentsVisible() {
    return getState(this.postStream)?.expanded ?? false;
  }

  // While collapsed we surface the count of hidden replies (which includes
  // live MessageBus arrivals). While expanded we fall back to the topic's
  // reply count (only used to decide whether to render the toggle at all).
  get replyCount() {
    if (this.commentsVisible) {
      return this.topic?.replyCount || 0;
    }
    return getState(this.postStream)?.hiddenCount ?? 0;
  }

  get hasReplies() {
    if (this.commentsVisible) {
      return (this.topic?.replyCount || 0) > 0;
    }
    return this.replyCount > 0;
  }

  get toggleLabel() {
    if (this.commentsVisible) {
      return i18n("doc_categories.simple_mode.hide_comments");
    }
    return i18n("doc_categories.simple_mode.show_comments", {
      count: this.replyCount,
    });
  }

  @action
  toggleComments() {
    if (!this.postStream) {
      return;
    }
    if (this.commentsVisible) {
      collapseStream(this.postStream);
    } else {
      expandStream(this.postStream);
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
          <DButton
            @action={{this.toggleComments}}
            @translatedLabel={{this.toggleLabel}}
            class="btn-default doc-simple-mode-toggle__button"
          />
        </div>
      {{/if}}
    {{/if}}
  </template>
}
