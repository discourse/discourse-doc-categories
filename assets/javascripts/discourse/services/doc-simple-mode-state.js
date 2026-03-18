import { tracked } from "@glimmer/tracking";
import Service from "@ember/service";

const COMMENTS_VISIBLE_CLASS = "doc-simple-mode--comments-visible";

export default class DocSimpleModeState extends Service {
  @tracked commentsVisible = false;
  _topicId = null;

  setTopicId(topicId) {
    if (this._topicId !== topicId) {
      this._topicId = topicId;
      this.commentsVisible = false;
      document.body.classList.remove(COMMENTS_VISIBLE_CLASS);
    }
  }

  showComments() {
    this.commentsVisible = true;
    document.body.classList.add(COMMENTS_VISIBLE_CLASS);
  }

  hideComments() {
    this.commentsVisible = false;
    document.body.classList.remove(COMMENTS_VISIBLE_CLASS);
  }

  reset() {
    this.commentsVisible = false;
    this._topicId = null;
    document.body.classList.remove(COMMENTS_VISIBLE_CLASS);
  }
}
