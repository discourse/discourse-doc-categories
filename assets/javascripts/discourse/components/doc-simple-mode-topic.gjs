import Component from "@glimmer/component";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import didUpdate from "@ember/render-modifiers/modifiers/did-update";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { service } from "@ember/service";
import isDocCategory from "../lib/is-doc-category";
import normalizeSimpleModeTopicUrl from "../lib/normalize-simple-mode-topic-url";

const BODY_CLASS = "doc-simple-mode";

export default class DocSimpleModeTopic extends Component {
  @service siteSettings;
  @service docSimpleModeState;

  get isSimpleMode() {
    return (
      this.siteSettings.doc_categories_simple_mode &&
      isDocCategory(this.args.outletArgs.model?.category)
    );
  }

  @action
  syncBodyClass() {
    if (this.isSimpleMode) {
      this.docSimpleModeState.setTopicId(this.args.outletArgs.model?.id);
      document.body.classList.add(BODY_CLASS);
      normalizeSimpleModeTopicUrl(this.args.outletArgs.model?.url);
    } else {
      document.body.classList.remove(BODY_CLASS);
    }
  }

  @action
  teardown() {
    document.body.classList.remove(BODY_CLASS);
  }

  <template>
    <span
      hidden
      data-doc-topic-id={{@outletArgs.model.id}}
      {{didInsert this.syncBodyClass}}
      {{didUpdate this.syncBodyClass @outletArgs.model.id}}
      {{willDestroy this.teardown}}
    ></span>
  </template>
}
