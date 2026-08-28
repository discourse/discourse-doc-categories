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
import DMenu from "discourse/float-kit/components/d-menu";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import discourseLater from "discourse/lib/later";
import { not } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DComboButton from "discourse/ui-kit/d-combo-button";
import DConditionalInElement from "discourse/ui-kit/d-conditional-in-element";
import DDragHandle from "discourse/ui-kit/d-drag-handle";
import DDropdownMenu from "discourse/ui-kit/d-dropdown-menu";
import DReorderableList from "discourse/ui-kit/d-reorderable-list";
import DReorderableListGroup from "discourse/ui-kit/d-reorderable-list-group";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import icon from "discourse/ui-kit/helpers/d-icon";
import dDragAndDropAutoScroll from "discourse/ui-kit/modifiers/d-drag-and-drop-auto-scroll";
import dDragAndDropSource from "discourse/ui-kit/modifiers/d-drag-and-drop-source";
import { i18n } from "discourse-i18n";
import validateDocIndexSections from "../../lib/doc-index-validation";
import { LINK_DRAG_TYPE } from "./link";
import { IndexEditorSection, SECTION_DRAG_TYPE } from "./section";

/**
 * A stable string identity per section, for the reorderable group to address
 * its members by.
 *
 * Sections carry a server `id` only once saved, so a new one has none and two
 * new ones would collide on `null`. Held outside the section rather than as a
 * field on it, so it never reaches the serializer or the transient-data
 * round-trip.
 */
const SECTION_UIDS = new WeakMap();
let nextSectionUid = 0;

function sectionUid(section) {
  let uid = SECTION_UIDS.get(section);
  if (!uid) {
    uid = `doc-index-section-${nextSectionUid++}`;
    SECTION_UIDS.set(section, uid);
  }
  return uid;
}

/* Main index editor */
export default class DocCategoryIndexEditor extends Component {
  @service dialog;

  @tracked sections = trackedArray(this.#initSections());
  @tracked saveState = null;
  @tracked includeSubcategories = false;
  @tracked
  autoIndexIncludeSubcategories =
    this.args.category?.doc_category_auto_index_include_subcategories ?? false;
  @tracked pendingResync = false;
  @tracked batchMode = false;
  @tracked isBatchDragging = false;
  @tracked batchDragType = null;

  selectedItems = trackedSet();
  selectedSections = trackedSet();

  #originalAutoIndexIncludeSubcategories =
    this.args.category?.doc_category_auto_index_include_subcategories ?? false;
  #saveStateTimer = null;
  @tracked _hasLocalChanges = false;

  constructor() {
    super(...arguments);
    this.args.onRegisterEditor?.(this);
    this.args.registerAfterReset?.(() => {
      this.sections = trackedArray(this.#initSectionsFromModel());
      this.batchMode = false;
      this.selectedItems.clear();
      this.selectedSections.clear();
    });
  }

  willDestroy() {
    super.willDestroy();
    if (this.#saveStateTimer) {
      cancel(this.#saveStateTimer);
      this.#saveStateTimer = null;
    }
    // Only persist editor state if the mode is still "direct" (topic_id === -1).
    // When switching to "none" mode, #applyNoneMode() already set the correct
    // form values -- overwriting them here would send stale data to the backend.
    if (Number(this.args.transientData?.doc_index_topic_id) === -1) {
      this._saveToTransientData();
    }
  }

  get serializedSections() {
    const serialized = this.#serializeSections();
    return serialized.length > 0 ? JSON.stringify(serialized) : null;
  }

  get searchFilters() {
    if (!this.args.categoryId) {
      return "in:title include:unlisted";
    }
    return `in:title include:unlisted category:=${this.args.categoryId}`;
  }

  get editingCount() {
    let count = 0;
    for (const section of this.sections) {
      if (section.isEditingTitle) {
        count++;
      }
      for (const link of section.links) {
        if (link.isEditing) {
          count++;
        }
      }
    }
    return count;
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

  get subcategorySettingChanged() {
    return (
      this.autoIndexIncludeSubcategories !==
      this.#originalAutoIndexIncludeSubcategories
    );
  }

  get hasPendingChanges() {
    return (
      this._hasLocalChanges ||
      this.args.transientData?._docIndexEditorState != null
    );
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

  get applyDisabled() {
    return (
      this.saveState === "saving" ||
      !this.hasPendingChanges ||
      this.validationErrors.length > 0
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

  @bind
  isFirstSection(section) {
    return this.sections.indexOf(section) === 0;
  }

  @bind
  cancelNewSection(section) {
    const idx = this.sections.indexOf(section);
    if (idx !== -1) {
      this.sections.splice(idx, 1);
    }
    this._saveToTransientData();
  }

  /**
   * Returns the confirmation rather than firing and forgetting it: the list
   * waits on it before announcing the removal and re-placing focus, so a
   * cancelled dialog is not spoken as a removal that happened.
   */
  @bind
  removeSection(section) {
    const message = section.autoIndex
      ? i18n(
          "doc_categories.category_settings.index_editor.confirm_remove_auto_index_section"
        )
      : i18n(
          "doc_categories.category_settings.index_editor.confirm_remove_section"
        );

    return this.dialog.yesNoConfirm({
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

  /**
   * A section reorder, as the list proposes it.
   *
   * @param move - The normalized move; only the proposed order is read, since
   *   the list has already resolved which row went where.
   */
  @bind
  applySectionMove({ proposedFromItems }) {
    this.sections.splice(0, this.sections.length, ...proposedFromItems);
    this._saveToTransientData();
  }

  /**
   * A link reorder, within one section or across two of them.
   *
   * Both halves are addressed by the group's list id rather than by the link,
   * because a cross-section move rewrites two sections and the link itself says
   * nothing about which pair.
   *
   * @param move - The normalized move.
   */
  @bind
  applyLinkMove({ fromList, toList, proposedFromItems, proposedToItems }) {
    const from = this.#sectionFor(fromList);
    if (!from) {
      return;
    }
    from.links.splice(0, from.links.length, ...proposedFromItems);

    if (toList !== fromList) {
      const to = this.#sectionFor(toList);
      if (to) {
        to.links.splice(0, to.links.length, ...proposedToItems);
        // A link landing in a collapsed section would otherwise disappear. A
        // drag opens one by dwelling over it; a keyboard move has no dwell.
        to.collapsed = false;
      }
    }
    this._saveToTransientData();
  }

  /** What to call a section, for its handle, menu entry and announcements. */
  @bind
  sectionLabel(section) {
    return this.#sectionLabel(section);
  }

  /** The section a group list id names. */
  #sectionFor(listId) {
    return this.sections.find((section) => sectionUid(section) === listId);
  }

  /** What to call a section a link has just landed in. */
  #sectionLabel(section) {
    return (
      section.title?.trim() ||
      i18n(
        "doc_categories.category_settings.index_editor.first_section_no_title"
      )
    );
  }

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
  isItemSelected(link) {
    return this.selectedItems.has(link);
  }

  @bind
  isSectionSelected(section) {
    return this.selectedSections.has(section);
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
    const sections = this.#serializeSections();
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

  @action
  addSection() {
    // Non-first sections with empty titles auto-enter edit mode
    const willAutoEdit = this.sections.length > 0;
    this.sections.push(
      trackedObject({
        title: "",
        links: trackedArray([]),
        isEditingTitle: willAutoEdit,
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

  @action
  toggleIncludeSubcategories() {
    this.includeSubcategories = !this.includeSubcategories;
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
        didConfirm: () => this.#doIndexAllTopics(),
      });
    } else {
      this.#doIndexAllTopics();
    }
  }

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
      this.args.form?.commitField("_docIndexAutoIndexIncludeSubcategories");
      this.#originalAutoIndexIncludeSubcategories =
        this.autoIndexIncludeSubcategories;
      this.args.category?.set("doc_index_sections", null);

      if (response.index_structure) {
        this.#refreshFromServerData(response.index_structure);
      }
      this.#saveStateTimer = discourseLater(() => {
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

  /**
   * A batch publishes the type of whatever is selected, so the rows that
   * already accept that kind accept the batch too and no target has to learn
   * what a batch is.
   */
  get batchSourceType() {
    return this.selectedSections.size > 0 ? SECTION_DRAG_TYPE : LINK_DRAG_TYPE;
  }

  @action
  canDragBatch() {
    return this.canDragSelection;
  }

  @action
  batchDragStart() {
    this.batchDragType = this.selectedSections.size > 0 ? "sections" : "items";
    this.isBatchDragging = true;
  }

  @action
  batchDragEnd() {
    this.isBatchDragging = false;
    this.batchDragType = null;
  }

  #initSections() {
    // Restore the subcategory toggle from transient data (tab switch recovery)
    const savedIncludeSub =
      this.args.transientData?._docIndexAutoIndexIncludeSubcategories;
    if (savedIncludeSub != null) {
      this.autoIndexIncludeSubcategories = savedIncludeSub;
    }

    // Restore from FormKit transient data if available (tab switch recovery)
    const saved = this.args.transientData?._docIndexEditorState;
    if (saved?.length > 0) {
      return saved.map((section, idx) =>
        trackedObject({
          id: section.id ?? null,
          title: section.title,
          autoIndex: section.autoIndex || false,
          isEditingTitle: idx > 0 && !section.title,
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
                isEditing: !link.title && !link.href,
              })
            )
          ),
        })
      );
    }

    return this.#initSectionsFromModel();
  }

  #initSectionsFromModel() {
    return this.#buildSectionsFrom(this.args.indexData);
  }

  #buildSectionsFrom(index) {
    if (!index || index.length === 0) {
      return [];
    }
    return index.map((section, idx) =>
      trackedObject({
        id: section.id ?? null,
        title: section.text,
        autoIndex: section.auto_index || false,
        isEditingTitle: idx > 0 && !section.text,
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

  #refreshFromServerData(indexStructure) {
    const newSections = this.#buildSectionsFrom(indexStructure);
    this.sections.splice(0, this.sections.length, ...newSections);
  }

  #serializeSections() {
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

  async #doIndexAllTopics() {
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
          links: trackedArray(result.topics.map((t) => this.#topicToLink(t))),
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

  #topicToLink(topic) {
    return trackedObject({
      title: topic.title || topic.fancy_title,
      href: `/t/${topic.slug}/${topic.id}`,
      type: "topic",
      icon: "far-file",
      topic_id: topic.id,
      topicTitle: topic.title || topic.fancy_title,
      autoTitle: true,
    });
  }

  <template>
    {{! The page scrolls, not the editor: it has no scroll container of its own,
        so a row dragged toward the viewport edge has to move the window or a
        long index cannot be reordered end to end without dropping halfway. }}
    <div
      {{! Untyped: the reorderable lists keep their drag tokens to themselves,
          and this page has no drag it would be wrong to scroll for. }}
      {{dDragAndDropAutoScroll target="window"}}
      class={{dConcatClass
        "doc-category-index-editor"
        (if this.batchMode "--batch-mode")
      }}
    >
      <DConditionalInElement @element={{@toolbarElement}} @append={{true}}>
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
              @placement="bottom-end"
              @triggerClass="btn-default doc-category-index-editor__options-trigger"
            >
              <:trigger>
                {{icon "wrench"}}
              </:trigger>
              <:content as |menuArgs|>
                <DDropdownMenu as |dropdown|>
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
                </DDropdownMenu>
              </:content>
            </DMenu>
          </div>
        {{/unless}}
      </DConditionalInElement>

      {{#if this.batchMode}}
        <div class="doc-category-index-editor__batch-bar">
          {{#if this.canDragSelection}}
            <DDragHandle
              {{dDragAndDropSource
                type=this.batchSourceType
                canDrag=this.canDragBatch
                onDragStart=this.batchDragStart
                onDragEnd=this.batchDragEnd
              }}
              @label={{i18n
                "doc_categories.category_settings.index_editor.drag_selection"
              }}
              class="doc-category-index-editor__batch-drag-handle"
            />
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

      {{! One group over every section's links, so a link travels between
          sections the same way it travels within one. The sections themselves
          are an ordinary standalone list nested inside it; the two never see
          each other's drags, since a standalone list carries a private token
          and a member carries the group's. }}
      <DReorderableListGroup @onMove={{this.applyLinkMove}} as |group|>
        <DReorderableList
          @items={{this.sections}}
          @label={{this.sectionLabel}}
          @onMove={{this.applySectionMove}}
          @onRemove={{this.removeSection}}
          @disabled={{this.batchMode}}
          @controls="manual"
          @tag="div"
          @itemTag="div"
          @rowClass="doc-category-index-editor__section-row"
          class="doc-category-index-editor__sections"
        >
          <:empty>
            <p class="doc-category-index-editor__empty">
              {{i18n "doc_categories.category_settings.index_editor.empty"}}
            </p>
          </:empty>
          <:row as |section controls|>
            <IndexEditorSection
              @section={{section}}
              @sectionUid={{sectionUid section}}
              @group={{group}}
              @controls={{controls}}
              @isFirstSection={{this.isFirstSection}}
              @categoryId={{@categoryId}}
              @searchFilters={{this.searchFilters}}
              @duplicateHrefs={{this.duplicateHrefs}}
              @duplicateTitles={{this.duplicateTitles}}
              @favoriteIcons={{this.favoriteIcons}}
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
              @onCancelNew={{this.cancelNewSection}}
              @onBatchSectionDrop={{this.batchReorderSections}}
              @onBatchItemDrop={{this.batchReorderItems}}
              @fetchTopics={{this.fetchTopics}}
              @autoIndexIncludeSubcategories={{this.autoIndexIncludeSubcategories}}
              @onToggleAutoIndexIncludeSubcategories={{this.toggleAutoIndexIncludeSubcategories}}
              @pendingResync={{this.pendingResync}}
              @hideResyncToggle={{this.subcategorySettingChanged}}
              @onToggleResyncAutoIndex={{this.toggleResyncAutoIndex}}
              @onChange={{this._saveToTransientData}}
            />
          </:row>
        </DReorderableList>
      </DReorderableListGroup>

      <DConditionalInElement
        @element={{@footerElement}}
        @inline={{not @footerElement}}
        @append={{true}}
      >
        {{#unless this.batchMode}}
          <div class="doc-category-index-editor__footer">
            <DComboButton @hasMenu={{not this.hasAutoIndexSection}}>
              <:default as |combo|>
                <combo.Button
                  @action={{this.addSection}}
                  @icon="plus"
                  @label="doc_categories.category_settings.index_editor.add_section"
                  class="btn-default btn-small"
                />
                {{! The menu is gated by @hasMenu, so guarding it here as well
                    would be the same condition written twice. }}
                <combo.Menu
                  @identifier="add-section-menu"
                  class="btn-default btn-small"
                >
                  <DDropdownMenu as |dropdown|>
                    <dropdown.item>
                      <DButton
                        @icon="bolt"
                        @label="doc_categories.category_settings.index_editor.add_auto_index_section"
                        @action={{this.addAutoIndexSection}}
                        class="btn-transparent"
                      />
                    </dropdown.item>
                  </DDropdownMenu>
                </combo.Menu>
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
      </DConditionalInElement>
    </div>
  </template>
}
