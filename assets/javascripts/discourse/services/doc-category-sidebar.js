import { tracked } from "@glimmer/tracking";
import Service, { inject as service } from "@ember/service";
import { MAIN_PANEL } from "discourse/lib/sidebar/panels";
import { deepEqual } from "discourse-common/lib/object";
import { bind } from "discourse-common/utils/decorators";

export const SIDEBAR_DOCS_PANEL = "discourse-docs-sidebar";

export default class DocCategorySidebarService extends Service {
  @service appEvents;
  @service router;
  @service messageBus;
  @service sidebarState;
  @service store;

  @tracked _indexCategoryId = null;
  @tracked _indexConfig = null;

  constructor() {
    super(...arguments);

    this.appEvents.on("page:changed", this, this.#maybeForceDocsSidebar);
    this.messageBus.subscribe("/categories", this.maybeUpdateIndexContent);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.messageBus.unsubscribe("/categories", this.maybeUpdateIndexContent);
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

  disableDocsSidebar() {
    this.hideDocsSidebar();
    this._indexCategoryId = null;
    this._indexConfig = null;
  }

  @bind
  maybeUpdateIndexContent(data) {
    const updatedIndex = data.categories?.find(
      (c) => c.id === this._indexCategoryId
    )?.doc_category_index;
    if (updatedIndex) {
      this.#setSidebarContent(this._indexCategoryId, updatedIndex);
      return;
    }

    if (data.deleted_categories?.find((id) => id === this._indexCategoryId)) {
      this.disableDocsSidebar();
    }
  }

  #findIndexForActiveCategory() {
    let category = this.activeCategory;

    while (category != null) {
      const categoryId = category.id;
      const indexConfig = category.doc_category_index;

      if (indexConfig) {
        return { categoryId, indexConfig };
      }

      category = category.parentCategory;
    }

    return {};
  }

  #maybeForceDocsSidebar() {
    const { categoryId, indexConfig: newIndexConfig } =
      this.#findIndexForActiveCategory();

    if (!newIndexConfig) {
      this.disableDocsSidebar();
      return;
    }

    if (
      this._indexCategoryId !== categoryId ||
      !deepEqual(this._indexConfig, newIndexConfig)
    ) {
      this.#setSidebarContent(categoryId, newIndexConfig);
    }
  }

  #setSidebarContent(categoryId, indexConfig) {
    if (!indexConfig) {
      this.disableDocsSidebar();
      return;
    }

    this._indexCategoryId = categoryId;
    this._indexConfig = indexConfig;
    this.showDocsSidebar();
  }
}
