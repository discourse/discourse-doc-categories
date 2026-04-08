import Component from "@glimmer/component";
import { cached, tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import {
  trackedArray,
  trackedObject,
  trackedSet,
} from "@ember/reactive/collections";
import { cancel } from "@ember/runloop";
import { service } from "@ember/service";
import ConditionalInElement from "discourse/components/conditional-in-element";
import DButton from "discourse/components/d-button";
import DComboButton from "discourse/components/d-combo-button";
import DropdownMenu from "discourse/components/dropdown-menu";
import DMenu from "discourse/float-kit/components/d-menu";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import discourseLater from "discourse/lib/later";
import { not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import validateDocIndexSections from "../../lib/doc-index-validation";
import { IndexEditorSection } from "./section";

/* Main index editor */
export default class DocCategoryIndexEditor extends Component {
  @service dialog;

  @tracked sections = trackedArray(this.initSections());
  @tracked saveState = null;
  @tracked includeSubcategories = false;
  @tracked
  autoIndexIncludeSubcategories =
    this.args.category?.doc_category_auto_index_include_subcategories ?? false;
  @tracked pendingResync = false;
  @tracked isDraggingSection = false;
  @tracked batchMode = false;
  @tracked editingCount = 0;
  @tracked isBatchDragging = false;
  @tracked batchDragType = null;
  selectedItems = trackedSet();
  selectedSections = trackedSet();
  draggedSection = null;
  #originalAutoIndexIncludeSubcategories =
    this.args.category?.doc_category_auto_index_include_subcategories ?? false;

  @tracked _hasLocalChanges = false;

  _draggedLink = null;
  _draggedLinkSourceSection = null;
  _saveStateTimer = null;

  constructor() {
    super(...arguments);
    this.args.onRegisterEditor?.(this);
    this.args.registerAfterReset?.(() => {
      this.sections = trackedArray(this._initSectionsFromModel());
      this.batchMode = false;
      this.selectedItems.clear();
      this.selectedSections.clear();
    });
  }

  willDestroy() {
    super.willDestroy();
    if (this._saveStateTimer) {
      cancel(this._saveStateTimer);
      this._saveStateTimer = null;
    }
    // Only persist editor state if the mode is still "direct" (topic_id === -1).
    // When switching to "none" mode, #applyNoneMode() already set the correct
    // form values -- overwriting them here would send stale data to the backend.
    if (Number(this.args.transientData?.doc_index_topic_id) === -1) {
      this._saveToTransientData();
    }
  }

  get serializedSections() {
    const serialized = this._serializeSections();
    return serialized.length > 0 ? JSON.stringify(serialized) : null;
  }

  initSections() {
    // Restore the subcategory toggle from transient data (tab switch recovery)
    const savedIncludeSub =
      this.args.transientData?._docIndexAutoIndexIncludeSubcategories;
    if (savedIncludeSub != null) {
      this.autoIndexIncludeSubcategories = savedIncludeSub;
    }

    // Restore from FormKit transient data if available (tab switch recovery)
    const saved = this.args.transientData?._docIndexEditorState;
    if (saved?.length > 0) {
      return saved.map((section) =>
        trackedObject({
          id: section.id ?? null,
          title: section.title,
          autoIndex: section.autoIndex || false,
          links: trackedArray(
            section.links.map((link) =>
              trackedObject({
                title: link.title,
                href: link.href,
                type: link.type || "topic",
                topic_id: link.topic_id,
                topicTitle: link.topicTitle,
                autoTitle: link.autoTitle,
                icon: link.icon || "far-file",
                autoIndexed: link.autoIndexed || false,
              })
            )
          ),
        })
      );
    }

    return this._initSectionsFromModel();
  }

  _initSectionsFromModel() {
    return this._buildSectionsFrom(this.args.indexData);
  }

  _buildSectionsFrom(index) {
    if (!index || index.length === 0) {
      return [];
    }
    return index.map((section) =>
      trackedObject({
        id: section.id ?? null,
        title: section.text,
        autoIndex: section.auto_index || false,
        links: trackedArray(
          section.links.map((link) =>
            trackedObject({
              title: link.text,
              href: link.href,
              type: link.topic_id ? "topic" : "manual",
              topic_id: link.topic_id ?? null,
              topicTitle: link.topic_title,
              autoTitle: link.topic_id && !link.custom_title,
              icon: link.icon || "far-file",
              autoIndexed: link.auto_indexed || false,
            })
          )
        ),
      })
    );
  }

  _refreshFromServerData(indexStructure) {
    const newSections = this._buildSectionsFrom(indexStructure);
    this.sections.splice(0, this.sections.length, ...newSections);
  }

  _serializeSections() {
    return this.sections.map((section) => ({
      id: section.id,
      title: section.title,
      autoIndex: section.autoIndex || false,
      links: section.links.map((link) => ({
        title: link.title,
        href: link.href,
        type: link.type,
        topic_id: link.topic_id,
        topicTitle: link.topicTitle,
        autoTitle: link.autoTitle,
        icon: link.icon,
        autoIndexed: link.autoIndexed || false,
      })),
    }));
  }

  get searchFilters() {
    if (!this.args.categoryId) {
      return "in:title include:unlisted";
    }
    return `in:title include:unlisted category:=${this.args.categoryId}`;
  }

  /**
   * Persists the current editor state to FormKit so it survives tab switches
   * and is available for "Save Category". Two form fields are maintained:
   *
   * - `_docIndexEditorState`: Rich camelCase array used to restore the full
   *   editor UI on tab-switch recovery (includes UI-only fields like
   *   `topicTitle`, `autoTitle`, `type`, and `autoIndexed`).
   * - `doc_index_sections`: Lean snake_case JSON string sent to the backend
   *   via `registerCategorySaveProperty` when "Save Category" is clicked.
   *
   * Both fields must be committed after a successful Apply to clear the
   * "Save Category" banner.
   */
  @bind
  _saveToTransientData() {
    const sections = this._serializeSections();
    this._hasLocalChanges = true;
    this.args.form?.set("_docIndexEditorState", sections);
    this.args.form?.set(
      "_docIndexAutoIndexIncludeSubcategories",
      this.autoIndexIncludeSubcategories
    );

    // Convert to snake_case for the backend payload
    const backendSections = sections.map((section) => ({
      id: section.id,
      title: section.title,
      auto_index: section.autoIndex || false,
      links: section.links.map((link) => ({
        title: link.title,
        href: link.href,
        topic_id: link.topic_id,
        icon: link.icon,
      })),
    }));
    const serialized =
      backendSections.length > 0 ? JSON.stringify(backendSections) : null;
    this.args.form?.set("doc_index_sections", serialized);
    if (serialized) {
      this.args.form?.set("doc_index_topic_id", -1);
    }
  }

  get isEmpty() {
    return this.sections.length === 0;
  }

  @cached
  get validationErrors() {
    const errors = [];

    if (this.editingCount > 0) {
      errors.push(
        i18n(
          "doc_categories.category_settings.index_editor.validation_pending_changes"
        )
      );
    }

    errors.push(...validateDocIndexSections(this.sections));
    return errors;
  }

  @cached
  get duplicateHrefs() {
    const counts = new Map();
    for (const section of this.sections) {
      for (const link of section.links) {
        if (link.href) {
          counts.set(link.href, (counts.get(link.href) || 0) + 1);
        }
      }
    }
    const dupes = new Set();
    for (const [href, count] of counts) {
      if (count > 1) {
        dupes.add(href);
      }
    }
    return dupes;
  }

  @cached
  get duplicateTitles() {
    const counts = new Map();
    for (const section of this.sections) {
      const title = section.title?.toLowerCase();
      if (title) {
        counts.set(title, (counts.get(title) || 0) + 1);
      }
    }
    const dupes = new Set();
    for (const [title, count] of counts) {
      if (count > 1) {
        dupes.add(title);
      }
    }
    return dupes;
  }

  @cached
  get favoriteIcons() {
    const icons = new Set(["far-file", "link"]);
    for (const section of this.sections) {
      for (const link of section.links) {
        if (link.icon) {
          icons.add(link.icon);
        }
      }
    }
    return [...icons];
  }

  get hasAutoIndexSection() {
    return this.sections.some((s) => s.autoIndex);
  }

  @action
  addSection() {
    this.sections.push(
      trackedObject({
        title: "",
        links: trackedArray([]),
      })
    );
    this._saveToTransientData();
  }

  @action
  addAutoIndexSection() {
    if (this.hasAutoIndexSection) {
      return;
    }
    this.sections.push(
      trackedObject({
        title: i18n(
          "doc_categories.category_settings.index_editor.auto_index_section_title"
        ),
        autoIndex: true,
        links: trackedArray([]),
      })
    );
    this._saveToTransientData();
  }

  @bind
  cancelNewSection(section) {
    const idx = this.sections.indexOf(section);
    if (idx !== -1) {
      this.sections.splice(idx, 1);
    }
    this._saveToTransientData();
  }

  @bind
  removeSection(section) {
    const message = section.autoIndex
      ? i18n(
          "doc_categories.category_settings.index_editor.confirm_remove_auto_index_section"
        )
      : i18n(
          "doc_categories.category_settings.index_editor.confirm_remove_section"
        );

    this.dialog.yesNoConfirm({
      message,
      didConfirm: () => {
        const idx = this.sections.indexOf(section);
        if (idx !== -1) {
          this.sections.splice(idx, 1);
        }
        this._saveToTransientData();
      },
    });
  }

  /* Section drag */
  @bind
  setDraggedSection(section) {
    this.draggedSection = section;
    this.isDraggingSection = true;
  }

  @bind
  clearDraggedSection() {
    this.draggedSection = null;
    this.isDraggingSection = false;
  }

  @bind
  reorderSection(targetSection, isAbove) {
    // Handle link dropped on section body (not on a specific link)
    if (this._draggedLink) {
      const sourceLinks = this._draggedLinkSourceSection.links;
      const draggedIdx = sourceLinks.indexOf(this._draggedLink);
      if (draggedIdx !== -1) {
        sourceLinks.splice(draggedIdx, 1);
      }
      targetSection.links.push(this._draggedLink);
      this._draggedLink = null;
      this._draggedLinkSourceSection = null;
      this._saveToTransientData();
      return;
    }

    if (!this.draggedSection || this.draggedSection === targetSection) {
      return;
    }
    const draggedIdx = this.sections.indexOf(this.draggedSection);
    if (draggedIdx === -1) {
      return;
    }
    this.sections.splice(draggedIdx, 1);
    let targetIdx = this.sections.indexOf(targetSection);
    if (!isAbove) {
      targetIdx++;
    }
    this.sections.splice(targetIdx, 0, this.draggedSection);
    this.draggedSection = null;
    this.isDraggingSection = false;
    this._saveToTransientData();
  }

  /* Cross-section link drag */
  @bind
  onLinkDragStart(link, sourceSection) {
    this._draggedLink = link;
    this._draggedLinkSourceSection = sourceSection;
  }

  @bind
  onLinkDrop(targetLink, targetSection, isAbove) {
    if (!this._draggedLink || this._draggedLink === targetLink) {
      this._draggedLink = null;
      this._draggedLinkSourceSection = null;
      return;
    }

    const sourceLinks = this._draggedLinkSourceSection.links;
    const draggedIdx = sourceLinks.indexOf(this._draggedLink);
    if (draggedIdx !== -1) {
      sourceLinks.splice(draggedIdx, 1);
    }

    const targetLinks = targetSection.links;
    let targetIdx = targetLinks.indexOf(targetLink);
    if (!isAbove) {
      targetIdx++;
    }
    targetLinks.splice(targetIdx, 0, this._draggedLink);

    this._draggedLink = null;
    this._draggedLinkSourceSection = null;
    this._saveToTransientData();
  }

  /* Topic fetching */
  @bind
  async fetchTopics(includeSubcategories) {
    const response = await ajax(
      `/doc-categories/indexes/${this.args.categoryId}/topics`,
      { data: { include_subcategories: includeSubcategories } }
    );
    return {
      topics: response.topics || [],
      totalCount: response.total_count ?? 0,
      truncated: (response.total_count ?? 0) > (response.topics || []).length,
    };
  }

  _topicToLink(topic) {
    return trackedObject({
      title: topic.title || topic.fancy_title,
      href: `/t/${topic.slug}/${topic.id}`,
      type: "topic",
      icon: "far-file",
    });
  }

  @action
  toggleIncludeSubcategories() {
    this.includeSubcategories = !this.includeSubcategories;
  }

  get subcategorySettingChanged() {
    return (
      this.autoIndexIncludeSubcategories !==
      this.#originalAutoIndexIncludeSubcategories
    );
  }

  @action
  toggleResyncAutoIndex(closeMenu) {
    closeMenu?.();
    this.pendingResync = !this.pendingResync;
    this._saveToTransientData();
  }

  @action
  toggleAutoIndexIncludeSubcategories(closeMenu) {
    closeMenu?.();

    // Toggling back to the original value doesn't trigger a resync,
    // so no confirmation is needed.
    const newValue = !this.autoIndexIncludeSubcategories;
    if (newValue === this.#originalAutoIndexIncludeSubcategories) {
      this.autoIndexIncludeSubcategories = newValue;
      this.pendingResync = false;
      this._saveToTransientData();
      return;
    }

    this.dialog.yesNoConfirm({
      message: i18n(
        "doc_categories.category_settings.index_editor.include_subcategories_confirm"
      ),
      didConfirm: () => {
        this.autoIndexIncludeSubcategories = newValue;
        this.pendingResync = false;
        this._saveToTransientData();
      },
    });
  }

  @action
  indexAllTopics(closeMenu) {
    closeMenu?.();
    if (this.sections.length > 0) {
      this.dialog.yesNoConfirm({
        message: i18n(
          "doc_categories.category_settings.index_editor.auto_populate_confirm"
        ),
        didConfirm: () => this._doIndexAllTopics(),
      });
    } else {
      this._doIndexAllTopics();
    }
  }

  async _doIndexAllTopics() {
    try {
      const result = await this.fetchTopics(this.includeSubcategories);
      if (this.isDestroying || this.isDestroyed) {
        return;
      }
      if (result.topics.length === 0) {
        return;
      }
      this.sections.splice(
        0,
        this.sections.length,
        trackedObject({
          title: i18n(
            "doc_categories.category_settings.index_editor.all_topics_section"
          ),
          links: trackedArray(result.topics.map((t) => this._topicToLink(t))),
        })
      );
      this._saveToTransientData();
      if (result.truncated) {
        this.dialog.alert(
          i18n(
            "doc_categories.category_settings.index_editor.topics_truncated",
            {
              loaded: result.topics.length,
              total: result.totalCount,
            }
          )
        );
      }
    } catch (e) {
      popupAjaxError(e);
    }
  }

  /* Apply (saves doc-index only, without saving category) */
  @action
  async apply() {
    if (this.validationErrors.length > 0) {
      this.saveState = "error";
      this.args.onApplyError?.(this.validationErrors.join(" "));
      return;
    }
    this.saveState = "saving";
    const payload = {
      force_direct: true,
      auto_index_include_subcategories: this.autoIndexIncludeSubcategories,
      force_sync: this.pendingResync,
      sections: this.sections.map((section) => ({
        id: section.id,
        title: section.title,
        auto_index: section.autoIndex || false,
        links: section.links.map((link) => ({
          title: link.title,
          href: link.href,
          topic_id: link.topic_id,
          icon: link.icon,
        })),
      })),
    };

    try {
      const response = await ajax(
        `/doc-categories/indexes/${this.args.categoryId}`,
        {
          type: "PUT",
          data: JSON.stringify(payload),
          contentType: "application/json",
        }
      );
      if (this.isDestroying || this.isDestroyed) {
        return;
      }
      this.saveState = "saved";
      this.pendingResync = false;
      this._hasLocalChanges = false;
      this.args.form?.set("_docIndexEditorState", null);
      this.args.form?.commitField("_docIndexEditorState");
      this.args.form?.commitField("doc_index_sections");
      this.args.form?.commitField("doc_index_topic_id");
      this.args.category?.set("doc_index_sections", null);

      if (response.index_structure) {
        this._refreshFromServerData(response.index_structure);
      }
      this._saveStateTimer = discourseLater(() => {
        if (!this.isDestroying && this.saveState === "saved") {
          this.saveState = null;
        }
      }, 3000);
    } catch (e) {
      if (this.isDestroying || this.isDestroyed) {
        return;
      }
      this.saveState = "error";
      popupAjaxError(e);
    }
  }

  get applyLabel() {
    switch (this.saveState) {
      case "saving":
        return "doc_categories.category_settings.index_editor.applying";
      case "saved":
        return "doc_categories.category_settings.index_editor.applied";
      default:
        return "doc_categories.category_settings.index_editor.apply";
    }
  }

  get hasPendingChanges() {
    return (
      this._hasLocalChanges ||
      this.args.transientData?._docIndexEditorState != null
    );
  }

  get canToggleBatchMode() {
    if (this.editingCount > 0) {
      return false;
    }

    if (this.sections.length === 0) {
      return false;
    }

    // Disable when there's only one section with at most one link
    if (this.sections.length === 1) {
      return this.sections[0].links.length > 1;
    }

    return true;
  }

  get selectionCount() {
    return this.selectedItems.size + this.selectedSections.size;
  }

  get hasSelection() {
    return this.selectionCount > 0;
  }

  get isMixedSelection() {
    return this.selectedItems.size > 0 && this.selectedSections.size > 0;
  }

  get canDragSelection() {
    return this.hasSelection && !this.isMixedSelection;
  }

  get selectionLabel() {
    const items = this.selectedItems.size;
    const sections = this.selectedSections.size;
    if (items > 0 && sections > 0) {
      return i18n(
        "doc_categories.category_settings.index_editor.batch_selected_mixed",
        { items, sections }
      );
    } else if (sections > 0) {
      return i18n(
        "doc_categories.category_settings.index_editor.batch_selected_sections",
        { count: sections }
      );
    }
    return i18n(
      "doc_categories.category_settings.index_editor.batch_selected_items",
      { count: items }
    );
  }

  @action
  toggleBatchMode() {
    if (this.batchMode && this.hasSelection) {
      this.dialog.yesNoConfirm({
        message: i18n(
          "doc_categories.category_settings.index_editor.batch_exit_confirm"
        ),
        didConfirm: () => {
          this.batchMode = false;
          this.selectedItems.clear();
          this.selectedSections.clear();
        },
      });
      return;
    }
    this.batchMode = !this.batchMode;
    if (!this.batchMode) {
      this.selectedItems.clear();
      this.selectedSections.clear();
    }
  }

  @bind
  onEditStateChange(isEditing) {
    if (isEditing) {
      this.editingCount++;
    } else {
      this.editingCount = Math.max(0, this.editingCount - 1);
    }
  }

  @bind
  toggleItemSelection(link) {
    if (this.selectedItems.has(link)) {
      this.selectedItems.delete(link);
    } else {
      this.selectedItems.add(link);
    }
  }

  @bind
  toggleSectionSelection(section) {
    if (this.selectedSections.has(section)) {
      this.selectedSections.delete(section);
    } else {
      this.selectedSections.add(section);
    }
  }

  @bind
  isFirstSection(section) {
    return this.sections.indexOf(section) === 0;
  }

  @bind
  isItemSelected(link) {
    return this.selectedItems.has(link);
  }

  @bind
  isSectionSelected(section) {
    return this.selectedSections.has(section);
  }

  @action
  clearSelection() {
    this.selectedItems.clear();
    this.selectedSections.clear();
  }

  @action
  selectAll() {
    if (this.selectedSections.size > 0) {
      for (const section of this.sections) {
        this.selectedSections.add(section);
      }
    } else {
      for (const section of this.sections) {
        for (const link of section.links) {
          this.selectedItems.add(link);
        }
      }
    }
  }

  @action
  invertSelection() {
    if (this.selectedSections.size > 0) {
      for (const section of this.sections) {
        if (this.selectedSections.has(section)) {
          this.selectedSections.delete(section);
        } else {
          this.selectedSections.add(section);
        }
      }
    } else {
      for (const section of this.sections) {
        for (const link of section.links) {
          if (this.selectedItems.has(link)) {
            this.selectedItems.delete(link);
          } else {
            this.selectedItems.add(link);
          }
        }
      }
    }
  }

  @bind
  selectAllInSection(section) {
    for (const link of section.links) {
      this.selectedItems.add(link);
    }
  }

  @bind
  clearAllInSection(section) {
    for (const link of section.links) {
      this.selectedItems.delete(link);
    }
  }

  @bind
  invertSelectionInSection(section) {
    for (const link of section.links) {
      if (this.selectedItems.has(link)) {
        this.selectedItems.delete(link);
      } else {
        this.selectedItems.add(link);
      }
    }
  }

  @action
  clearIndex(closeMenu) {
    closeMenu?.();
    if (this.sections.length === 0) {
      return;
    }
    this.dialog.yesNoConfirm({
      message: i18n(
        "doc_categories.category_settings.index_editor.clear_index_confirm"
      ),
      didConfirm: () => {
        this.sections.splice(0, this.sections.length);
        this._saveToTransientData();
      },
    });
  }

  @action
  bulkDelete() {
    this.dialog.yesNoConfirm({
      message: i18n(
        "doc_categories.category_settings.index_editor.batch_delete_confirm"
      ),
      didConfirm: () => {
        for (const section of this.selectedSections) {
          const idx = this.sections.indexOf(section);
          if (idx !== -1) {
            this.sections.splice(idx, 1);
          }
        }
        for (const link of this.selectedItems) {
          for (const section of this.sections) {
            const idx = section.links.indexOf(link);
            if (idx !== -1) {
              section.links.splice(idx, 1);
              break;
            }
          }
        }
        this.selectedItems.clear();
        this.selectedSections.clear();
        this._saveToTransientData();
      },
    });
  }

  @action
  batchDragStart(event) {
    if (!this.canDragSelection) {
      event.preventDefault();
      return;
    }
    event.dataTransfer.effectAllowed = "move";
    this.batchDragType = this.selectedSections.size > 0 ? "sections" : "items";
    this.isBatchDragging = true;
  }

  @action
  batchDragEnd() {
    this.isBatchDragging = false;
    this.batchDragType = null;
  }

  @bind
  batchReorderSections(targetSection, isAbove) {
    // Dropping on a selected section is a no-op
    if (this.selectedSections.has(targetSection)) {
      this.isBatchDragging = false;
      this.batchDragType = null;
      return;
    }

    const ordered = this.sections.filter((s) => this.selectedSections.has(s));
    for (const s of ordered) {
      const idx = this.sections.indexOf(s);
      if (idx !== -1) {
        this.sections.splice(idx, 1);
      }
    }
    let targetIdx = this.sections.indexOf(targetSection);
    if (!isAbove) {
      targetIdx++;
    }
    this.sections.splice(targetIdx, 0, ...ordered);
    this.isBatchDragging = false;
    this.batchDragType = null;
    this._saveToTransientData();
  }

  @bind
  batchReorderItems(targetLink, targetSection, isAbove) {
    // Dropping on a selected item is a no-op
    if (targetLink && this.selectedItems.has(targetLink)) {
      this.isBatchDragging = false;
      this.batchDragType = null;
      return;
    }

    // Collect selected items preserving their current order across all sections
    const ordered = [];
    for (const section of this.sections) {
      for (const link of section.links) {
        if (this.selectedItems.has(link)) {
          ordered.push(link);
        }
      }
    }

    // Remove selected items from their source sections
    for (const link of ordered) {
      for (const section of this.sections) {
        const idx = section.links.indexOf(link);
        if (idx !== -1) {
          section.links.splice(idx, 1);
          break;
        }
      }
    }

    // Insert at target position (append to end if dropped on section body)
    if (targetLink) {
      let targetIdx = targetSection.links.indexOf(targetLink);
      if (!isAbove) {
        targetIdx++;
      }
      targetSection.links.splice(targetIdx, 0, ...ordered);
    } else {
      targetSection.links.push(...ordered);
    }

    this.isBatchDragging = false;
    this.batchDragType = null;
    this._saveToTransientData();
  }

  get applyDisabled() {
    return (
      this.saveState === "saving" ||
      !this.hasPendingChanges ||
      this.validationErrors.length > 0
    );
  }

  <template>
    <div
      class={{concatClass
        "doc-category-index-editor"
        (if this.batchMode "--batch-mode")
      }}
    >
      <ConditionalInElement @element={{@toolbarElement}} @append={{true}}>
        {{#unless this.batchMode}}
          <div class="doc-category-index-editor__toolbar-actions">
            <DButton
              @icon="list-check"
              @label="doc_categories.category_settings.index_editor.batch_edit"
              @action={{this.toggleBatchMode}}
              @disabled={{not this.canToggleBatchMode}}
              class="btn-default"
            />
            <DMenu
              @identifier="index-options-menu"
              @triggerClass="btn-default doc-category-index-editor__options-trigger"
            >
              <:trigger>
                {{icon "wrench"}}
              </:trigger>
              <:content as |menuArgs|>
                <DropdownMenu as |dropdown|>
                  <dropdown.item>
                    <DButton
                      @icon="arrows-rotate"
                      @label="doc_categories.category_settings.index_editor.index_all_topics"
                      @action={{fn this.indexAllTopics menuArgs.close}}
                      class="btn-transparent"
                    />
                  </dropdown.item>
                  <dropdown.item>
                    <label
                      class="doc-category-index-editor__subcategory-toggle"
                    >
                      <input
                        type="checkbox"
                        checked={{this.includeSubcategories}}
                        {{on "change" this.toggleIncludeSubcategories}}
                      />
                      {{i18n
                        "doc_categories.category_settings.index_editor.include_subcategories"
                      }}
                    </label>
                  </dropdown.item>
                  <dropdown.divider />
                  <dropdown.item>
                    <DButton
                      @icon="trash-can"
                      @label="doc_categories.category_settings.index_editor.clear_index"
                      @action={{fn this.clearIndex menuArgs.close}}
                      class="btn-transparent doc-category-index-editor__clear-index-btn"
                    />
                  </dropdown.item>
                </DropdownMenu>
              </:content>
            </DMenu>
          </div>
        {{/unless}}
      </ConditionalInElement>

      {{#if this.batchMode}}
        <div class="doc-category-index-editor__batch-bar">
          {{#if this.canDragSelection}}
            <span
              class="doc-category-index-editor__batch-drag-handle"
              draggable="true"
              role="button"
              aria-label={{i18n
                "doc_categories.category_settings.index_editor.drag_selection"
              }}
              {{on "dragstart" this.batchDragStart}}
              {{on "dragend" this.batchDragEnd}}
            >
              {{icon "grip-lines"}}
            </span>
          {{/if}}

          <span class="doc-category-index-editor__batch-count">
            {{#if this.hasSelection}}
              {{this.selectionLabel}}
            {{else}}
              {{i18n
                "doc_categories.category_settings.index_editor.batch_select_hint"
              }}
            {{/if}}
          </span>

          <div class="doc-category-index-editor__batch-actions">
            {{#if this.hasSelection}}
              <DButton
                @icon="trash-can"
                @action={{this.bulkDelete}}
                @title="doc_categories.category_settings.index_editor.batch_delete"
                class="btn-flat btn-small doc-category-index-editor__batch-delete-btn"
              />
            {{/if}}
            <DButton
              @icon="check-double"
              @action={{this.selectAll}}
              @title="doc_categories.category_settings.index_editor.batch_select_all"
              class="btn-flat btn-small"
            />
            <DButton
              @icon="right-left"
              @action={{this.invertSelection}}
              @title="doc_categories.category_settings.index_editor.batch_invert"
              class="btn-flat btn-small"
            />
            <DButton
              @icon="eraser"
              @action={{this.clearSelection}}
              @title="doc_categories.category_settings.index_editor.batch_clear_selection"
              class="btn-flat btn-small"
            />
            <DButton
              @icon="xmark"
              @action={{this.toggleBatchMode}}
              @title="doc_categories.category_settings.index_editor.batch_close"
              class="btn-flat btn-small"
            />
          </div>
        </div>
      {{/if}}

      {{#if this.isEmpty}}
        <p class="doc-category-index-editor__empty">
          {{i18n "doc_categories.category_settings.index_editor.empty"}}
        </p>
      {{/if}}

      <div class="doc-category-index-editor__sections">
        {{#each this.sections as |section|}}
          <IndexEditorSection
            @section={{section}}
            @isFirstSection={{this.isFirstSection}}
            @categoryId={{@categoryId}}
            @searchFilters={{this.searchFilters}}
            @duplicateHrefs={{this.duplicateHrefs}}
            @duplicateTitles={{this.duplicateTitles}}
            @favoriteIcons={{this.favoriteIcons}}
            @isDraggingSection={{this.isDraggingSection}}
            @isBatchDragging={{this.isBatchDragging}}
            @batchDragType={{this.batchDragType}}
            @batchMode={{this.batchMode}}
            @isSectionSelected={{this.isSectionSelected}}
            @isItemSelected={{this.isItemSelected}}
            @toggleSectionSelection={{this.toggleSectionSelection}}
            @toggleItemSelection={{this.toggleItemSelection}}
            @selectAllInSection={{this.selectAllInSection}}
            @clearAllInSection={{this.clearAllInSection}}
            @invertSelectionInSection={{this.invertSelectionInSection}}
            @onEditStateChange={{this.onEditStateChange}}
            @onRemove={{this.removeSection}}
            @onCancelNew={{this.cancelNewSection}}
            @onSectionDragStart={{this.setDraggedSection}}
            @onSectionDragEnd={{this.clearDraggedSection}}
            @onSectionDrop={{this.reorderSection}}
            @onBatchSectionDrop={{this.batchReorderSections}}
            @onLinkDragStart={{this.onLinkDragStart}}
            @onLinkDrop={{this.onLinkDrop}}
            @onBatchItemDrop={{this.batchReorderItems}}
            @fetchTopics={{this.fetchTopics}}
            @autoIndexIncludeSubcategories={{this.autoIndexIncludeSubcategories}}
            @onToggleAutoIndexIncludeSubcategories={{this.toggleAutoIndexIncludeSubcategories}}
            @pendingResync={{this.pendingResync}}
            @hideResyncToggle={{this.subcategorySettingChanged}}
            @onToggleResyncAutoIndex={{this.toggleResyncAutoIndex}}
            @onChange={{this._saveToTransientData}}
          />
        {{/each}}
      </div>

      <ConditionalInElement
        @element={{@footerElement}}
        @inline={{not @footerElement}}
        @append={{true}}
      >
        {{#unless this.batchMode}}
          <div class="doc-category-index-editor__footer">
            <DComboButton class="--has-menu btn-small">
              <:default as |combo|>
                <combo.Button
                  @action={{this.addSection}}
                  @icon="plus"
                  @label="doc_categories.category_settings.index_editor.add_section"
                />
                {{#unless this.hasAutoIndexSection}}
                  <combo.Menu @identifier="add-section-menu">
                    <DropdownMenu as |dropdown|>
                      <dropdown.item>
                        <DButton
                          @icon="bolt"
                          @label="doc_categories.category_settings.index_editor.add_auto_index_section"
                          @action={{this.addAutoIndexSection}}
                          class="btn-transparent"
                        />
                      </dropdown.item>
                    </DropdownMenu>
                  </combo.Menu>
                {{/unless}}
              </:default>
            </DComboButton>
          </div>
        {{/unless}}

        <div class="doc-category-index-editor__apply-footer">
          <DButton
            @icon="check"
            @label={{this.applyLabel}}
            @action={{this.apply}}
            @disabled={{this.applyDisabled}}
            class="btn-primary btn-small doc-category-index-editor__apply-btn"
          />
        </div>
      </ConditionalInElement>
    </div>
  </template>
}
