import { tracked } from "@glimmer/tracking";
import { schedule } from "@ember/runloop";
import Service, { inject as service } from "@ember/service";
import { TrackedMap } from "@ember-compat/tracked-built-ins";
import { MAIN_PANEL } from "discourse/lib/sidebar/panels";
import { deepEqual } from "discourse-common/lib/object";
import { bind } from "discourse-common/utils/decorators";
import {
  generateSectionLinkName,
  generateSectionName,
  isSectionLinkActive,
} from "../lib/doc-category-sidebar-panel";

export const SIDEBAR_DOCS_PANEL = "discourse-docs-sidebar";

export default class DocCategorySidebarService extends Service {
  @service appEvents;
  @service router;
  @service messageBus;
  @service sidebarState;
  @service store;

  @tracked _currentActiveSectionName = null;
  @tracked _currentActiveSectionLinkName = null;
  @tracked _indexCategoryId = null;
  @tracked _indexConfig = null;
  _sectionCollapsedStateTracker = new TrackedMap();

  constructor() {
    super(...arguments);

    this.appEvents.on("page:changed", this, this.maybeForceDocsSidebar);
    this.appEvents.on(
      "sidebar-state:collapse-section",
      this,
      this.#trackCollapsedSection
    );
    this.appEvents.on(
      "sidebar-state:expand-section",
      this,
      this.#trackExpandedSection
    );
    this.messageBus.subscribe("/categories", this.maybeUpdateIndexContent);
  }

  willDestroy() {
    super.willDestroy(...arguments);

    this.appEvents.off("page:changed", this, this.maybeForceDocsSidebar);
    this.appEvents.off(
      "sidebar-state:collapse-section",
      this,
      this.#trackCollapsedSection
    );
    this.appEvents.off(
      "sidebar-state:expand-section",
      this,
      this.#trackExpandedSection
    );
    this.messageBus.unsubscribe("/categories", this.maybeUpdateIndexContent);
  }

  get activeCategory() {
    return (
      this.router.currentRoute?.attributes?.category ||
      this.router.currentRoute?.parent?.attributes?.category
    );
  }

  get isVisible() {
    return this.sidebarState.isCurrentPanel(SIDEBAR_DOCS_PANEL);
  }

  get sectionsConfig() {
    return this._indexConfig || [];
  }

  get activeSectionInfo() {
    let linkConfig = null;
    const sectionConfig = this.sectionsConfig.find((section) => {
      linkConfig = section.links?.find((link) =>
        isSectionLinkActive(this.router, link)
      );

      return !!linkConfig;
    });

    return sectionConfig ? { sectionConfig, linkConfig } : null;
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
    this._currentActiveSectionName = null;
    this._currentActiveSectionLinkName = null;
  }

  @bind
  maybeForceDocsSidebar(opts = {}) {
    const { categoryId, indexConfig: newIndexConfig } =
      this.#findIndexForCategory(opts.category);

    if (!newIndexConfig) {
      this.disableDocsSidebar();
      return;
    }

    if (
      this._indexCategoryId !== categoryId ||
      !deepEqual(this._indexConfig, newIndexConfig)
    ) {
      this.#setSidebarContent(categoryId, newIndexConfig);
      return;
    }

    this.#maybeExpandActiveSection();
  }

  @bind
  maybeUpdateIndexContent(data) {
    // if the docs sidebar is not displayed, tries to display it
    if (!this.isVisible) {
      this.maybeForceDocsSidebar();
      return;
    }

    // if the docs sidebar is displayed, checks if the index needs to be updated for the current category
    const updatedCategory = data.categories?.find(
      (c) => c.id === this._indexCategoryId
    );

    if (updatedCategory) {
      this.#setSidebarContent(
        this._indexCategoryId,
        updatedCategory.doc_category_index
      );
    }

    // if the category no longer exists hides the docs sidebar
    if (data.deleted_categories?.find((id) => id === this._indexCategoryId)) {
      this.disableDocsSidebar();
    }
  }

  #findIndexForCategory(category) {
    category ??= this.activeCategory;

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

  #setSidebarContent(categoryId, indexConfig) {
    if (!indexConfig) {
      this.disableDocsSidebar();
      return;
    }

    this._indexCategoryId = categoryId;
    this._indexConfig = indexConfig;
    this.showDocsSidebar();
    this.#maybeExpandActiveSection();
  }

  #maybeExpandActiveSection() {
    const oldActiveSectionName = this._currentActiveSectionName;
    const oldActiveSectionLinkName = this._currentActiveSectionLinkName;

    const newActiveSectionInfo = this.activeSectionInfo;
    const newActiveSectionName = newActiveSectionInfo
      ? generateSectionName(newActiveSectionInfo.sectionConfig)
      : null;
    const newActiveSectionLinkName = newActiveSectionInfo?.linkConfig
      ? generateSectionLinkName(
          newActiveSectionName,
          newActiveSectionInfo.linkConfig
        )
      : null;

    // skip if the active section link did not change
    if (oldActiveSectionLinkName === newActiveSectionLinkName) {
      return;
    }

    // only act if we have a tracked value for the old active section name
    if (this._sectionCollapsedStateTracker.has(oldActiveSectionName)) {
      if (this._sectionCollapsedStateTracker.get(oldActiveSectionName)) {
        this.sidebarState.collapsedSections.add(oldActiveSectionName);
      } else {
        this.sidebarState.collapsedSections.delete(oldActiveSectionName);
      }
    }

    // expand the new active section
    if (newActiveSectionName) {
      this.sidebarState.collapsedSections.delete(newActiveSectionName);
    }

    // scroll the new active link into view
    if (newActiveSectionLinkName) {
      schedule("afterRender", () => {
        const itemElement = document.querySelector(
          `li[data-list-item-name='${newActiveSectionLinkName}']`
        );

        itemElement?.scrollIntoView({
          block: "center",
        });
      });
    }

    // update the current active section and link
    this._currentActiveSectionName = newActiveSectionName;
    this._currentActiveSectionLinkName = newActiveSectionLinkName;
  }

  #trackCollapsedSection(eventData) {
    this.#trackSectionCollapsedState(eventData.sectionKey, true);
  }

  #trackExpandedSection(eventData) {
    this.#trackSectionCollapsedState(eventData.sectionKey, false);
  }

  #trackSectionCollapsedState(sectionName, isCollapsed) {
    if (this.isVisible) {
      this._sectionCollapsedStateTracker.set(sectionName, isCollapsed);
    }
  }
}
