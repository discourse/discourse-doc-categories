import { tracked } from "@glimmer/tracking";
import Service, { inject as service } from "@ember/service";
import { isEmpty } from "@ember/utils";
import { ajax } from "discourse/lib/ajax";
import { MAIN_PANEL } from "discourse/lib/sidebar/panels";
import { parseSidebarStructure } from "../lib/doc-category-sidebar-structure-parser";

export const SIDEBAR_DOCS_PANEL = "discourse-docs-sidebar";

export default class DocsSidebarService extends Service {
  @service appEvents;
  @service router;
  @service sidebarState;
  @service store;

  #contentCache = new Map();
  @tracked _activeTopicId;
  @tracked _currentSectionsConfig = null;
  @tracked _loading = false;

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

  get allSectionsExpanded() {
    return this.sectionsConfig?.every((sectionConfig) => {
      return !this.sidebarState.collapsedSections.has(
        `sidebar-section-${sectionConfig.name}-collapsed`
      );
    });
  }

  get isEnabled() {
    return !!this._activeTopicId;
  }

  get isVisible() {
    return this.sidebarState.isCurrentPanel(SIDEBAR_DOCS_PANEL);
  }

  get loading() {
    return this._loading;
  }

  get sectionsConfig() {
    return this._currentSectionsConfig || [];
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
    this._activeTopicId = null;
    this._currentSectionsConfig = null;
  }

  #findSettingsForActiveCategory() {
    let category = this.activeCategory;

    while (category != null) {
      const matchingSetting = category.custom_fields?.doc_category_index_topic;

      if (matchingSetting) {
        return { indexTopicId: matchingSetting };
      }

      category = category.parentCategory;
    }
  }

  #maybeForceDocsSidebar() {
    const newActiveTopicId =
      this.#findSettingsForActiveCategory()?.indexTopicId;

    if (!newActiveTopicId) {
      this.disableDocsSidebar();
      return;
    }

    if (this._activeTopicId !== newActiveTopicId) {
      this.#setSidebarContent(newActiveTopicId);
    }
  }

  async #setSidebarContent(topic_id) {
    this._activeTopicId = topic_id;

    if (!this._activeTopicId) {
      this.hideDocsSidebar();
      return;
    }

    this._currentSectionsConfig = this.#contentCache.get(this._activeTopicId);

    if (this._currentSectionsConfig) {
      this.showDocsSidebar();
      return;
    }

    await this.#fetchTopicContent(topic_id);
  }

  async #fetchTopicContent(topic_id) {
    this._loading = true;
    this.showDocsSidebar();

    try {
      // leverages the post stream API to fetch only the first post
      const data = await ajax(`/t/${topic_id}/posts.json`, {
        post_number: 2,
        include_suggested: false,
        asc: false,
      });

      const cookedHtml = data?.post_stream?.posts?.[0]?.cooked;
      if (!cookedHtml) {
        // display regular sidebar
        return;
      }

      const sections = parseSidebarStructure(cookedHtml);

      // the parser will return only sections with at least one link
      // if none could be found, fallback to the default sidebar
      if (isEmpty(sections)) {
        this.disableDocsSidebar();
        return;
      }

      this.#contentCache.set(topic_id, sections);
      this._currentSectionsConfig = sections;
    } catch (error) {
      // if an error occurred while fetching the content, fallback to the default sidebar
      this.disableDocsSidebar();
    } finally {
      this._loading = false;
    }
  }
}
