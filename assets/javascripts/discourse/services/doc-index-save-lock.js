import { tracked } from "@glimmer/tracking";
import Service, { service } from "@ember/service";
import { bind } from "discourse/lib/decorators";

export default class DocIndexSaveLock extends Service {
  @service router;

  @tracked isSaving = false;

  constructor() {
    super(...arguments);
    this.router.on("routeWillChange", this._preventNavigation);
    window.addEventListener("beforeunload", this._preventUnload);
  }

  willDestroy() {
    super.willDestroy();
    this.router.off("routeWillChange", this._preventNavigation);
    window.removeEventListener("beforeunload", this._preventUnload);
  }

  @bind
  _preventNavigation(transition) {
    if (this.isSaving && !transition.isAborted) {
      transition.abort();
    }
  }

  @bind
  _preventUnload(event) {
    if (this.isSaving) {
      event.preventDefault();
      event.returnValue = "";
    }
  }
}
