import { tracked } from "@glimmer/tracking";
import Service, { inject as service } from "@ember/service";
import { MAIN_PANEL } from "discourse/lib/sidebar/panels";
import { deepEqual } from "discourse-common/lib/object";

export const SIDEBAR_DOCS_PANEL = "discourse-docs-sidebar";

export default class DocCategorySidebarService extends Service {
  @service appEvents;
  @service router;
  @service sidebarState;
  @service store;

  @tracked _indexConfig = null;

  constructor() {
    super(...arguments);

    this.appEvents.on("page:changed", this, this.#maybeForceDocsSidebar);
  }

  get activeCategory() {
    return (
      this.router.currentRoute?.attributes?.category ||
      this.router.currentRoute?.parent?.attributes?.category
    );
  }

  get isEnabled() {
    return !!this._activeIndex;
  }

  get isVisible() {
    return this.sidebarState.isCurrentPanel(SIDEBAR_DOCS_PANEL);
  }

  get loading() {
    return this._loading;
  }

  get sectionsConfig() {
    return this._indexConfig || [];
  }

  hideDocsSidebar() {
    if (!this.isVisible) {
      return;
    }

    this.sidebarState.setPanel(MAIN_PANEL);
  }

  showDocsSidebar() {
    this.sidebarState.setPanel(SIDEBAR_DOCS_PANEL);
    this.sidebarState.setSeparatedMode();
    this.sidebarState.hideSwitchPanelButtons();
  }

  toggleSidebarPanel() {
    if (this.isVisible) {
      this.hideDocsSidebar();
    } else {
      this.showDocsSidebar();
    }
  }

  disableDocsSidebar() {
    this.hideDocsSidebar();
    this._indexConfig = null;
  }

  #findIndexForActiveCategory() {
    let category = this.activeCategory;

    while (category != null) {
      const indexConfig = category.doc_category_index;

      if (indexConfig) {
        return indexConfig;
      }

      category = category.parentCategory;
    }
  }

  #maybeForceDocsSidebar() {
    const newIndexConfig = this.#findIndexForActiveCategory();

    if (!newIndexConfig) {
      this.disableDocsSidebar();
      return;
    }

    if (!deepEqual(this._indexConfig, newIndexConfig)) {
      this.#setSidebarContent(newIndexConfig);
    }
  }

  #setSidebarContent(index) {
    if (!index) {
      this.disableDocsSidebar();
      return;
    }

    this._indexConfig = index;
    this.showDocsSidebar();
  }
}
