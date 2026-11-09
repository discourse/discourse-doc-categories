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
import { cancel, next, schedule } from "@ember/runloop";
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
import DEmptyState from "discourse/ui-kit/d-empty-state";
import DReorderableList from "discourse/ui-kit/d-reorderable-list";
import DReorderableListGroup from "discourse/ui-kit/d-reorderable-list-group";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import icon from "discourse/ui-kit/helpers/d-icon";
import dDragAndDropAutoScroll from "discourse/ui-kit/modifiers/d-drag-and-drop-auto-scroll";
import dDragAndDropSource from "discourse/ui-kit/modifiers/d-drag-and-drop-source";
import { i18n } from "discourse-i18n";
import {
  MAX_LINKS_PER_SECTION,
  MAX_SECTION_DEPTH,
  MAX_SECTIONS,
} from "../../lib/constants.js";
import {
  isIndexSection,
  sectionEntries,
  sectionHeight,
  sectionLinks,
} from "../../lib/doc-index-tree.js";
import {
  draftTopicIds,
  draftTopicReferences,
  UnindexedTopicsCounter,
} from "../../lib/doc-index-unindexed-topics.js";
import validateDocIndexSections from "../../lib/doc-index-validation.js";
import { LINK_DRAG_TYPE } from "./link.gjs";
import { IndexEditorSection, SECTION_DRAG_TYPE } from "./section.gjs";
import UnindexedTopicsModal from "./unindexed-topics-modal.gjs";

/** The destination that creates a section rather than naming one. */
const NEW_SECTION = "new";
const ROOT_LIST = "doc-index-root";

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

function editorGroup(group, editor) {
  return {
    ...group,
    registerMember(member) {
      return group.registerMember({
        ...member,
        // All lists enter batch mode together. Read that state and the labels
        // from the editor so a parent never consumes a child's render arguments.
        disabled: () => editor.batchMode,
        listLabel: () => editor.listLabel(member.listId),
      });
    },
    neighbour(listId, direction) {
      const member = group.neighbour(listId, direction);
      if (member?.listId !== ROOT_LIST) {
        return member;
      }
    },
  };
}

const SectionRow = <template>
  <IndexEditorSection
    @autoIndexIncludeSubcategories={{@editor.autoIndexIncludeSubcategories}}
    @batchDragType={{@editor.batchDragType}}
    @batchMode={{@editor.batchMode}}
    @canAddChild={{@editor.canAddChild}}
    @canMoveOut={{@editor.canMoveOut}}
    @categoryId={{@categoryId}}
    @clearAllInSection={{@editor.clearAllInSection}}
    @controls={{@controls}}
    @duplicateHrefs={{@editor.duplicateHrefs}}
    @duplicateTitles={{@editor.duplicateTitles}}
    @favoriteIcons={{@editor.favoriteIcons}}
    @group={{@group}}
    @hideResyncToggle={{@editor.subcategorySettingChanged}}
    @invertSelectionInSection={{@editor.invertSelectionInSection}}
    @isBatchDragging={{@editor.isBatchDragging}}
    @isFirstSection={{@editor.isFirstSection}}
    @isItemSelected={{@editor.isItemSelected}}
    @isSectionSelected={{@editor.isSectionSelected}}
    @onAddSection={{@editor.addSection}}
    @onBatchItemDrop={{@editor.batchReorderItems}}
    @onBatchSectionDrop={{@editor.batchReorderSections}}
    @onBatchSectionDropInside={{@editor.batchMoveSectionsInside}}
    @onCancelNew={{@editor.cancelNewSection}}
    @onChange={{@editor._saveToTransientData}}
    @onMoveOut={{@editor.moveSectionOut}}
    @onRemoveSection={{@editor.removeSection}}
    @onReviewUnindexedTopics={{@editor.reviewUnindexedTopics}}
    @onToggleAutoIndexIncludeSubcategories={{@editor.toggleAutoIndexIncludeSubcategories}}
    @onToggleResyncAutoIndex={{@editor.toggleResyncAutoIndex}}
    @pendingResync={{@editor.pendingResync}}
    @searchFilters={{@editor.searchFilters}}
    @section={{@section}}
    @sectionDepth={{@editor.sectionDepth}}
    @sectionLimitReached={{@editor.sectionLimitReached}}
    @sectionPath={{@editor.sectionPath}}
    @sectionUid={{sectionUid @section}}
    @selectAllInSection={{@editor.selectAllInSection}}
    @toggleItemSelection={{@editor.toggleItemSelection}}
    @toggleSectionSelection={{@editor.toggleSectionSelection}}
    as |child controls|
  >
    <SectionRow
      @categoryId={{@categoryId}}
      @controls={{controls}}
      @editor={{@editor}}
      @group={{@group}}
      @section={{child}}
    />
  </IndexEditorSection>
</template>;

/* Main index editor */
export default class DocCategoryIndexEditor extends Component {
  @service a11y;
  @service dialog;
  @service docIndexSaveLock;
  @service modal;
  @service toasts;

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

  /** The objects the last review added, which Undo takes back exactly. */
  @tracked lastAddition = null;

  selectedItems = trackedSet();
  selectedSections = trackedSet();

  #originalAutoIndexIncludeSubcategories =
    this.args.category?.doc_category_auto_index_include_subcategories ?? false;
  #saveStateTimer = null;
  #additionToast = null;
  #unindexedCounter = new UnindexedTopicsCounter(this.args.categoryId);
  #lastDestination = null;
  @tracked _hasLocalChanges = false;

  constructor() {
    super(...arguments);
    this.args.onRegisterEditor?.(this);
    this.args.registerAfterReset?.(() => {
      if (this.isDestroying || this.docIndexSaveLock.isSaving) {
        return;
      }
      this.sections = trackedArray(this.#initSectionsFromModel());
      this.batchMode = false;
      this.selectedItems.clear();
      this.selectedSections.clear();
      this.dismissLastAddition();
      this.autoIndexIncludeSubcategories =
        this.#originalAutoIndexIncludeSubcategories;
      this.pendingResync = false;
      this._hasLocalChanges = false;
      this.#refreshUnindexedCount({ force: true, immediate: true });
    });
    this.#refreshUnindexedCount({ immediate: true });
  }

  willDestroy() {
    super.willDestroy();
    this.dismissLastAddition();
    this.#unindexedCounter.teardown();
    if (this.#saveStateTimer) {
      cancel(this.#saveStateTimer);
      this.#saveStateTimer = null;
    }
  }

  @cached
  get entries() {
    return [...sectionEntries(this.sections)];
  }

  get allSections() {
    return this.entries.map(({ section }) => section);
  }

  get allSectionsExpanded() {
    return this.allSections.every((section) => !section.collapsed);
  }

  get toggleAllSectionsIcon() {
    return this.allSectionsExpanded ? "angles-up" : "angles-down";
  }

  get toggleAllSectionsTitle() {
    return this.allSectionsExpanded
      ? "sidebar.collapse_all_sections"
      : "sidebar.expand_all_sections";
  }

  get sectionLimitReached() {
    return this.entries.length >= MAX_SECTIONS;
  }

  get sectionLimitMessage() {
    return i18n("doc_categories.category_settings.index_editor.section_limit", {
      count: MAX_SECTIONS,
    });
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
    for (const section of this.allSections) {
      if (section.isEditingTitle) {
        count++;
      }
      for (const link of sectionLinks(section)) {
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
    for (const section of this.allSections) {
      for (const link of sectionLinks(section)) {
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
    for (const section of this.allSections) {
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
    for (const section of this.allSections) {
      for (const link of sectionLinks(section)) {
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

  /** The auto-index's scope when there is one, so counts match what it collects. */
  get unindexedIncludesSubcategories() {
    return this.hasAutoIndexSection && this.autoIndexIncludeSubcategories;
  }

  /** Mirrors when the server's IndexSaver runs auto-index on Apply. */
  get autoIndexSyncPending() {
    const section = this.sections.find((s) => s.autoIndex);
    return (
      !!section &&
      (!section.id || this.pendingResync || this.subcategorySettingChanged)
    );
  }

  get showUnindexedTopics() {
    return !this.batchMode && this.#unindexedCounter.count > 0;
  }

  get unindexedTopicsMessage() {
    if (this.#unindexedCounter.isLoading) {
      return i18n(
        "doc_categories.category_settings.index_editor.unindexed_topics.checking"
      );
    }
    if (this.autoIndexSyncPending) {
      const section = this.sections.find((candidate) => candidate.autoIndex);
      const available = Math.max(
        0,
        MAX_LINKS_PER_SECTION - sectionLinks(section).length
      );
      return available === 0
        ? i18n(
            "doc_categories.category_settings.index_editor.unindexed_topics.auto_index_full"
          )
        : i18n(
            "doc_categories.category_settings.index_editor.unindexed_topics.auto_index_pending",
            { count: Math.min(available, this.#unindexedCounter.count) }
          );
    }

    const count = this.#unindexedCounter.count;
    return this.unindexedIncludesSubcategories
      ? i18n(
          "doc_categories.category_settings.index_editor.unindexed_topics.count_with_subcategories",
          { count }
        )
      : i18n(
          "doc_categories.category_settings.index_editor.unindexed_topics.count",
          { count }
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
    if (this.entries.length === 1) {
      return sectionLinks(this.sections[0]).length > 1;
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

  /**
   * A batch publishes the type of whatever is selected, so the rows that
   * already accept that kind accept the batch too and no target has to learn
   * what a batch is.
   */
  get batchSourceType() {
    return this.selectedSections.size > 0 ? SECTION_DRAG_TYPE : LINK_DRAG_TYPE;
  }

  get selectedSubtrees() {
    return this.entries
      .filter(
        ({ section, ancestors }) =>
          this.selectedSections.has(section) &&
          !ancestors.some((parent) => this.selectedSections.has(parent))
      )
      .map(({ section }) => section);
  }

  @bind
  isFirstSection(section) {
    return this.sections.indexOf(section) === 0;
  }

  @bind
  cancelNewSection(section) {
    this.#removeItem(this.#siblings(section), section);
    this._saveToTransientData();
  }

  @bind
  removeSection(section) {
    const remove = () => {
      this.#removeItem(this.#siblings(section), section);
      this._saveToTransientData();
    };

    if (!section.autoIndex && section.items.length === 0) {
      remove();
      return;
    }

    let message =
      "doc_categories.category_settings.index_editor.confirm_remove_section";
    if (section.autoIndex) {
      message =
        "doc_categories.category_settings.index_editor.confirm_remove_auto_index_section";
    } else if (section.items.some(isIndexSection)) {
      message =
        "doc_categories.category_settings.index_editor.confirm_remove_section_tree";
    }
    return this.dialog.yesNoConfirm({
      message: i18n(message),
      didConfirm: remove,
    });
  }

  @bind
  applyItemMove({
    item,
    fromList,
    toList,
    proposedFromItems,
    proposedToItems,
  }) {
    const from = this.#sectionFor(fromList);
    const to = this.#sectionFor(toList);
    if (!this.#canPlaceItems([item], to, proposedToItems)) {
      return false;
    }

    const sourceItems = from?.items ?? this.sections;
    sourceItems.splice(0, sourceItems.length, ...proposedFromItems);
    if (fromList !== toList) {
      const targetItems = to?.items ?? this.sections;
      targetItems.splice(0, targetItems.length, ...proposedToItems);
      this.#expandDestination(to);
    }
    this._saveToTransientData();
  }

  @bind
  sectionDepth(section) {
    return this.#ancestors(section).length + 1;
  }

  @bind
  canAddChild(section) {
    return (
      !!section.title?.trim() &&
      !section.autoIndex &&
      this.sectionDepth(section) < MAX_SECTION_DEPTH
    );
  }

  @bind
  canMoveOut(section) {
    return this.sectionDepth(section) > 1;
  }

  @bind
  moveSectionOut(section) {
    const ancestors = this.#ancestors(section);
    const parent = ancestors.at(-1);
    if (parent && this.#moveItems([section], ancestors.at(-2), parent, false)) {
      schedule("afterRender", () => {
        const row = document.querySelector(
          `[data-doc-index-section="${sectionUid(section)}"]`
        )?.parentElement;
        row
          ?.querySelector(":scope > .doc-category-index-editor__drag-handle")
          ?.focus();
      });
      this.a11y.announce(
        i18n(
          "doc_categories.category_settings.index_editor.moved_section_out",
          {
            section: this.#sectionLabel(section),
          }
        )
      );
    }
  }

  @bind
  sectionPath(section) {
    return [...this.#ancestors(section), section]
      .map((entry) => this.#sectionLabel(entry))
      .join(" / ");
  }

  /** What to call a section, for its handle, menu entry and announcements. */
  @bind
  sectionLabel(section) {
    return this.#sectionLabel(section);
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
    for (const link of sectionLinks(section)) {
      this.selectedItems.add(link);
    }
  }

  @bind
  clearAllInSection(section) {
    for (const link of sectionLinks(section)) {
      this.selectedItems.delete(link);
    }
  }

  @bind
  invertSelectionInSection(section) {
    for (const link of sectionLinks(section)) {
      if (this.selectedItems.has(link)) {
        this.selectedItems.delete(link);
      } else {
        this.selectedItems.add(link);
      }
    }
  }

  @bind
  batchReorderSections(targetSection, isAbove) {
    if (!this.selectedSections.has(targetSection)) {
      this.#moveItems(
        this.selectedSubtrees,
        this.#ancestors(targetSection).at(-1),
        targetSection,
        isAbove
      );
    }
    this.batchDragEnd();
  }

  @bind
  batchMoveSectionsInside(targetSection) {
    this.#moveItems(this.selectedSubtrees, targetSection);
    this.batchDragEnd();
  }

  @bind
  batchReorderItems(targetLink, targetSection, isAbove) {
    const selected = this.allSections.flatMap((section) =>
      sectionLinks(section).filter((link) => this.selectedItems.has(link))
    );
    if (!this.selectedItems.has(targetLink)) {
      this.#moveItems(selected, targetSection, targetLink, isAbove);
    }
    this.batchDragEnd();
  }

  @action
  reviewUnindexedTopics(section) {
    const preferred =
      [section, this.#lastDestination].find(
        (candidate) =>
          candidate &&
          !candidate.autoIndex &&
          this.allSections.includes(candidate)
      ) ?? this.allSections.findLast((candidate) => !candidate.autoIndex);

    this.modal.show(UnindexedTopicsModal, {
      model: {
        categoryId: this.args.categoryId,
        destinations: this.#unindexedDestinations(),
        initialDestination: preferred
          ? this.#destinationValue(preferred)
          : NEW_SECTION,
        includeSubcategories: this.unindexedIncludesSubcategories,
        canIncludeSubcategories:
          !!this.args.category?.has_children ||
          this.unindexedIncludesSubcategories,
        getReferences: () => draftTopicReferences(this.sections),
        addTopics: this.addUnindexedTopics,
      },
    });
  }

  /** Skips topics the draft already holds; returns `{ added }` or `{ error }`. */
  @bind
  addUnindexedTopics({ topics, destination }) {
    let section = null;
    if (destination === NEW_SECTION) {
      if (this.entries.length >= MAX_SECTIONS) {
        return {
          error: i18n(
            "doc_categories.category_settings.index_editor.unindexed_topics.too_many_sections"
          ),
        };
      }
    } else {
      section = this.allSections.find(
        (candidate) =>
          !candidate.autoIndex &&
          this.#destinationValue(candidate) === destination
      );
      if (!section) {
        return {
          error: i18n(
            "doc_categories.category_settings.index_editor.unindexed_topics.destination_missing"
          ),
        };
      }
    }

    const indexed = draftTopicIds(this.sections);
    const topicsToAdd = topics.filter((topic) => !indexed.has(topic.id));
    const room = Math.max(
      0,
      MAX_LINKS_PER_SECTION - (section ? sectionLinks(section).length : 0)
    );
    if (topicsToAdd.length > room) {
      return {
        error: i18n(
          room === 0
            ? "doc_categories.category_settings.index_editor.unindexed_topics.section_full"
            : "doc_categories.category_settings.index_editor.unindexed_topics.section_room",
          {
            section: section
              ? this.#sectionLabel(section)
              : this.#newSectionTitle(),
            count: room,
          }
        ),
      };
    }
    if (topicsToAdd.length === 0) {
      return { added: 0 };
    }

    let createdSection = null;
    if (!section) {
      section = createdSection = trackedObject({
        title: this.#newSectionTitle(),
        items: trackedArray([]),
      });
      this.sections.push(section);
      this.#moveAboveAutoIndex(section);
    }

    const links = topicsToAdd.map((topic) => this.#topicToLink(topic));
    section.items.push(...links);
    section.collapsed = false;
    this.#lastDestination = section;
    this.lastAddition = { links, section, createdSection };
    this._saveToTransientData();
    this.#additionToast = this.toasts.success({
      key: "doc-index-added-topics",
      duration: "long",
      data: {
        message: this.#additionSummary(this.lastAddition),
        actions: [
          {
            label: i18n(
              "doc_categories.category_settings.index_editor.unindexed_topics.undo"
            ),
            icon: "arrow-rotate-left",
            class: "btn-flat doc-category-index-editor__undo-add",
            action: this.undoLastAddition,
          },
        ],
      },
    });

    return { added: links.length };
  }

  /**
   * Takes back exactly the added links, wherever they have moved since. A
   * section the addition created goes too, unless something else joined it.
   */
  @action
  undoLastAddition() {
    if (this.docIndexSaveLock.isSaving) {
      return;
    }
    const addition = this.lastAddition;
    if (!addition) {
      return;
    }

    const added = new Set(addition.links);
    for (const section of this.allSections) {
      const kept = section.items.filter((item) => !added.has(item));
      if (kept.length !== section.items.length) {
        section.items.splice(0, section.items.length, ...kept);
      }
    }
    for (const link of addition.links) {
      this.selectedItems.delete(link);
    }

    const created = addition.createdSection;
    if (created && created.items.length === 0) {
      this.#removeItem(this.#siblings(created), created);
      this.selectedSections.delete(created);
    }

    this.dismissLastAddition();
    this._saveToTransientData();
    this.a11y.announce(
      i18n(
        "doc_categories.category_settings.index_editor.unindexed_topics.undone"
      )
    );
  }

  @action
  dismissLastAddition() {
    if (this.#additionToast) {
      this.toasts.close(this.#additionToast);
      this.#additionToast = null;
    }
    this.lastAddition = null;
  }

  @action
  addSection(parent) {
    if (this.sectionLimitReached || (parent && !this.canAddChild(parent))) {
      return;
    }
    // Non-first sections with empty titles auto-enter edit mode
    const items = parent?.items ?? this.sections;
    const willAutoEdit = !!parent || this.sections.length > 0;
    items.push(
      trackedObject({
        title: "",
        items: trackedArray([]),
        isEditingTitle: willAutoEdit,
      })
    );
    this._saveToTransientData();
  }

  @action
  addAutoIndexSection() {
    if (this.hasAutoIndexSection || this.sectionLimitReached) {
      return;
    }
    this.sections.push(
      trackedObject({
        title: i18n(
          "doc_categories.category_settings.index_editor.auto_index_section_title"
        ),
        autoIndex: true,
        items: trackedArray([]),
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
    if (this.docIndexSaveLock.isSaving) {
      return;
    }
    if (this.validationErrors.length > 0) {
      this.saveState = "error";
      this.args.onApplyError?.(this.validationErrors.join(" "));
      return;
    }
    const payload = {
      force_direct: true,
      auto_index_include_subcategories: this.autoIndexIncludeSubcategories,
      force_sync: this.pendingResync,
      sections: this.#buildPayload(),
    };

    this.saveState = "saving";
    this.docIndexSaveLock.isSaving = true;
    try {
      const response = await ajax(
        `/doc-categories/indexes/${this.args.categoryId}`,
        {
          type: "PUT",
          data: JSON.stringify(payload),
          contentType: "application/json",
        }
      );
      if (this.isDestroying) {
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
      // Undo would reach into a draft that has just been saved.
      this.dismissLastAddition();

      if (response.index_structure) {
        this.#refreshFromServerData(response.index_structure);
      }
      this.#refreshUnindexedCount({ force: true, immediate: true });
      this.args.onApplied?.(response.index_structure);
      this.#saveStateTimer = discourseLater(() => {
        if (!this.isDestroying && this.saveState === "saved") {
          this.saveState = null;
        }
      }, 3000);
    } catch (e) {
      if (this.isDestroying) {
        return;
      }
      this.saveState = "error";
      popupAjaxError(e);
    } finally {
      this.docIndexSaveLock.isSaving = false;
    }
  }

  @action
  toggleAllSections() {
    const collapse = this.allSectionsExpanded;
    this.allSections.forEach((section) => (section.collapsed = collapse));
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
      for (const section of this.allSections) {
        this.selectedSections.add(section);
      }
    } else {
      for (const section of this.allSections) {
        for (const link of sectionLinks(section)) {
          this.selectedItems.add(link);
        }
      }
    }
  }

  @action
  invertSelection() {
    if (this.selectedSections.size > 0) {
      for (const section of this.allSections) {
        if (this.selectedSections.has(section)) {
          this.selectedSections.delete(section);
        } else {
          this.selectedSections.add(section);
        }
      }
    } else {
      for (const section of this.allSections) {
        for (const link of sectionLinks(section)) {
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
          this.#removeItem(this.#siblings(section), section);
        }
        for (const link of this.selectedItems) {
          for (const section of this.allSections) {
            const idx = section.items.indexOf(link);
            if (idx !== -1) {
              section.items.splice(idx, 1);
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

  listLabel(listId) {
    const section = this.#sectionFor(listId);
    return section ? this.sectionPath(section) : undefined;
  }

  #sectionFor(listId) {
    return this.allSections.find((section) => sectionUid(section) === listId);
  }

  #ancestors(section) {
    return (
      this.entries.find((entry) => entry.section === section)?.ancestors ?? []
    );
  }

  #siblings(section) {
    return this.#ancestors(section).at(-1)?.items ?? this.sections;
  }

  #removeItem(items, item) {
    const position = items.indexOf(item);
    if (position !== -1) {
      items.splice(position, 1);
    }
  }

  #expandDestination(section) {
    if (section) {
      for (const entry of [...this.#ancestors(section), section]) {
        entry.collapsed = false;
      }
    }
  }

  #canPlaceItems(items, destination, proposedItems) {
    const sections = items.filter(isIndexSection);
    if (!destination && sections.length !== items.length) {
      this.#showMoveError("move_link_to_section");
      return false;
    }

    if (
      destination &&
      proposedItems.filter((item) => !isIndexSection(item)).length >
        MAX_LINKS_PER_SECTION
    ) {
      this.#showLinkLimit();
      return false;
    }

    if (destination && sections.length > 0) {
      const ancestors = [...this.#ancestors(destination), destination];
      if (
        !destination.title?.trim() ||
        destination.autoIndex ||
        sections.some(
          (section) =>
            section.autoIndex ||
            !section.title?.trim() ||
            ancestors.includes(section)
        )
      ) {
        this.#showMoveError("invalid_section_destination");
        return false;
      }
      if (
        sections.some(
          (section) =>
            ancestors.length + sectionHeight(section) > MAX_SECTION_DEPTH
        )
      ) {
        this.#showMoveError("section_depth_limit");
        return false;
      }
    }

    if (
      !destination &&
      proposedItems.some(
        (section, position) =>
          position > 0 && !section.title?.trim() && !section.isEditingTitle
      )
    ) {
      this.#showMoveError("untitled_section_must_be_first");
      return false;
    }

    return true;
  }

  #showMoveError(message) {
    this.toasts.error({
      key: "doc-index-section-move",
      data: {
        message: i18n(
          `doc_categories.category_settings.index_editor.${message}`,
          {
            count: MAX_SECTION_DEPTH,
          }
        ),
      },
    });
  }

  #moveItems(items, destination, target, before) {
    const targetItems = destination?.items ?? this.sections;
    const selected = new Set(items);
    const proposed = targetItems.filter((item) => !selected.has(item));
    if (target && !proposed.includes(target)) {
      return false;
    }
    const position = target
      ? proposed.indexOf(target) + (before ? 0 : 1)
      : proposed.length;
    proposed.splice(position, 0, ...items);
    if (!this.#canPlaceItems(items, destination, proposed)) {
      return false;
    }

    for (const item of items) {
      const source = isIndexSection(item)
        ? this.#siblings(item)
        : this.allSections.find((section) => section.items.includes(item))
            ?.items;
      if (source && source !== targetItems) {
        this.#removeItem(source, item);
      }
    }
    targetItems.splice(0, targetItems.length, ...proposed);
    this.#expandDestination(destination);
    this._saveToTransientData();
    return true;
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

  #initSections() {
    // Restore the subcategory toggle from transient data (tab switch recovery)
    const savedIncludeSub =
      this.args.transientData?._docIndexAutoIndexIncludeSubcategories;
    if (savedIncludeSub != null) {
      this.autoIndexIncludeSubcategories = savedIncludeSub;
    }

    // Restore from FormKit transient data if available (tab switch recovery)
    const saved = this.args.transientData?._docIndexEditorState;
    return saved?.length
      ? this.#readSections(saved, true)
      : this.#initSectionsFromModel();
  }

  #initSectionsFromModel() {
    return this.#readSections(this.args.indexData ?? []);
  }

  #readSections(sections, draft = false) {
    return sections.map((section, index) =>
      this.#readSection(section, draft, index === 0)
    );
  }

  #readSection(section, draft, first = false) {
    const title = draft ? section.title : section.text;
    const items = section.items ?? section.links ?? [];
    return trackedObject({
      id: section.id ?? null,
      title,
      autoIndex: draft ? section.autoIndex : section.auto_index,
      isEditingTitle: !first && !title,
      items: trackedArray(
        items.map((item) => {
          if (item.type === "section") {
            return this.#readSection(item, draft);
          }
          if (draft) {
            return trackedObject({
              ...item,
              isEditing: !item.title && !item.href,
            });
          }
          return trackedObject({
            title: item.text,
            href: item.href,
            type: item.topic_id ? "topic" : "manual",
            topic_id: item.topic_id ?? null,
            topicTitle: item.topic_title,
            autoTitle: item.topic_id && !item.custom_title,
            icon: item.icon || "far-file",
            autoIndexed: item.auto_indexed || false,
          });
        })
      ),
    });
  }

  #refreshFromServerData(indexStructure) {
    const newSections = this.#readSections(indexStructure);
    this.sections.splice(0, this.sections.length, ...newSections);
    // The selection holds the objects that were just replaced, so left alone
    // it survives as a count with no rows behind it.
    this.selectedItems.clear();
    this.selectedSections.clear();
  }

  #serializeSections() {
    const serialize = (section) => ({
      id: section.id,
      title: section.title,
      autoIndex: section.autoIndex || false,
      items: section.items.map((item) =>
        isIndexSection(item)
          ? { ...serialize(item), type: "section" }
          : {
              title: item.title,
              href: item.href,
              type: item.type,
              topic_id: item.topic_id,
              topicTitle: item.topicTitle,
              autoTitle: item.autoTitle,
              icon: item.icon,
              autoIndexed: item.autoIndexed || false,
            }
      ),
    });
    return this.sections.map(serialize);
  }

  #buildPayload() {
    const serialize = (section) => {
      const data = {
        id: section.id,
        title: section.title,
        auto_index: section.autoIndex || false,
      };
      const serializeLink = (link) => ({
        title: link.title,
        href: link.href,
        topic_id: link.topic_id,
        icon: link.icon,
      });
      if (section.items.some(isIndexSection)) {
        data.items = section.items.map((item) =>
          isIndexSection(item)
            ? { ...serialize(item), type: "section" }
            : { ...serializeLink(item), type: "link" }
        );
      } else {
        data.links = section.items.map(serializeLink);
      }
      return data;
    };
    return this.sections.map(serialize);
  }

  async #doIndexAllTopics() {
    try {
      const result = await this.fetchTopics(this.includeSubcategories);
      if (this.isDestroying || this.docIndexSaveLock.isSaving) {
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
          items: trackedArray(result.topics.map((t) => this.#topicToLink(t))),
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

  #refreshUnindexedCount(options) {
    this.#unindexedCounter.update(
      {
        references: draftTopicReferences(this.sections),
        includeSubcategories: this.unindexedIncludesSubcategories,
      },
      options
    );
  }

  #showLinkLimit() {
    this.toasts.error({
      key: "doc-index-capacity",
      data: {
        message: i18n(
          "doc_categories.category_settings.index_editor.link_limit",
          {
            count: MAX_LINKS_PER_SECTION,
          }
        ),
      },
    });
  }

  #unindexedDestinations() {
    const destinations = this.allSections
      .filter((section) => !section.autoIndex)
      .map((section) => ({
        value: this.#destinationValue(section),
        label: this.sectionPath(section),
        linkCount: sectionLinks(section).length,
      }));

    if (!this.sectionLimitReached) {
      destinations.push({
        value: NEW_SECTION,
        label: i18n(
          "doc_categories.category_settings.index_editor.unindexed_topics.new_section",
          { title: this.#newSectionTitle() }
        ),
        linkCount: 0,
      });
    }
    return destinations;
  }

  #newSectionTitle() {
    const base = i18n(
      "doc_categories.category_settings.index_editor.all_topics_section"
    );
    const titles = new Set(
      this.allSections.map((section) => section.title?.trim().toLowerCase())
    );
    let title = base;
    let count = 1;
    while (titles.has(title.toLowerCase())) {
      title = i18n(
        "doc_categories.category_settings.index_editor.unindexed_topics.numbered_section",
        { title: base, count: ++count }
      );
    }
    return title;
  }

  /**
   * Auto-index stays last, gathering what the sections above leave out. The
   * move waits a tick: a section rendered ahead of an existing one in the same
   * pass trips the reorderable group's backtracking assertion.
   */
  #moveAboveAutoIndex(section) {
    next(() => {
      if (this.isDestroying) {
        return;
      }
      const from = this.sections.indexOf(section);
      const to = this.sections.findIndex((s) => s.autoIndex);
      if (from === -1 || to === -1 || from < to) {
        return;
      }
      this.sections.splice(from, 1);
      this.sections.splice(to, 0, section);
      this._saveToTransientData();
    });
  }

  /** Unsaved sections have no id, so they borrow their reorder key. */
  #destinationValue(section) {
    return section.id ? String(section.id) : sectionUid(section);
  }

  #additionSummary(addition) {
    return i18n(
      "doc_categories.category_settings.index_editor.unindexed_topics.added",
      {
        count: addition.links.length,
        section: this.#sectionLabel(addition.section),
      }
    );
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

    const backendSections = this.#buildPayload();
    const serialized =
      backendSections.length > 0 ? JSON.stringify(backendSections) : null;
    this.args.form?.set("doc_index_sections", serialized);
    if (serialized) {
      this.args.form?.set("doc_index_topic_id", -1);
    }
    this.#refreshUnindexedCount();
  }

  <template>
    {{! The page scrolls, not the editor: it has no scroll container of its own,
        so a row dragged toward the viewport edge has to move the window or a
        long index cannot be reordered end to end without dropping halfway. }}
    <div
      class={{dConcatClass
        "doc-category-index-editor"
        (if this.batchMode "--batch-mode")
      }}
      inert={{this.docIndexSaveLock.isSaving}}
      {{! Untyped: the reorderable lists keep their drag tokens to themselves,
          and this page has no drag it would be wrong to scroll for. }}
      {{dDragAndDropAutoScroll target="window"}}
    >
      <DConditionalInElement @append={{true}} @element={{@toolbarElement}}>
        {{#unless this.batchMode}}
          <div class="doc-category-index-editor__toolbar-actions">
            <DButton
              class="btn-default doc-category-index-editor__toggle-all-sections"
              @action={{this.toggleAllSections}}
              @disabled={{not this.sections.length}}
              @icon={{this.toggleAllSectionsIcon}}
              @title={{this.toggleAllSectionsTitle}}
            />
            <DButton
              class="btn-default"
              @action={{this.toggleBatchMode}}
              @disabled={{not this.canToggleBatchMode}}
              @icon="list-check"
              @label="doc_categories.category_settings.index_editor.batch_edit"
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
                      class="btn-transparent"
                      @action={{fn this.indexAllTopics menuArgs.close}}
                      @icon="arrows-rotate"
                      @label="doc_categories.category_settings.index_editor.index_all_topics"
                    />
                  </dropdown.item>
                  <dropdown.item>
                    <label
                      class="doc-category-index-editor__subcategory-toggle"
                    >
                      <input
                        checked={{this.includeSubcategories}}
                        type="checkbox"
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
                      class="btn-transparent doc-category-index-editor__clear-index-btn"
                      @action={{fn this.clearIndex menuArgs.close}}
                      @icon="trash-can"
                      @label="doc_categories.category_settings.index_editor.clear_index"
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
              class="doc-category-index-editor__batch-drag-handle"
              @label={{i18n
                "doc_categories.category_settings.index_editor.drag_selection"
              }}
              {{dDragAndDropSource
                type=this.batchSourceType
                canDrag=this.canDragBatch
                onDragStart=this.batchDragStart
                onDragEnd=this.batchDragEnd
              }}
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
                class="btn-flat btn-small doc-category-index-editor__batch-delete-btn"
                @action={{this.bulkDelete}}
                @icon="trash-can"
                @title="doc_categories.category_settings.index_editor.batch_delete"
              />
            {{/if}}
            <DButton
              class="btn-flat btn-small"
              @action={{this.selectAll}}
              @icon="check-double"
              @title="doc_categories.category_settings.index_editor.batch_select_all"
            />
            <DButton
              class="btn-flat btn-small"
              @action={{this.invertSelection}}
              @icon="right-left"
              @title="doc_categories.category_settings.index_editor.batch_invert"
            />
            <DButton
              class="btn-flat btn-small"
              @action={{this.clearSelection}}
              @icon="eraser"
              @title="doc_categories.category_settings.index_editor.batch_clear_selection"
            />
            <DButton
              class="btn-flat btn-small"
              @action={{this.toggleBatchMode}}
              @icon="xmark"
              @title="doc_categories.category_settings.index_editor.batch_close"
            />
          </div>
        </div>
      {{/if}}

      {{#if this.showUnindexedTopics}}
        <div class="doc-category-index-editor__missing-topics">
          {{icon "circle-info"}}
          <span class="doc-category-index-editor__missing-topics-text">
            {{this.unindexedTopicsMessage}}
          </span>
          <DButton
            class="btn-default btn-small doc-category-index-editor__review-topics"
            @action={{this.reviewUnindexedTopics}}
            @label="doc_categories.category_settings.index_editor.unindexed_topics.review"
          />
        </div>
      {{/if}}

      <DReorderableListGroup @onMove={{this.applyItemMove}} as |group|>
        {{#let (editorGroup group this) as |reorderGroup|}}
          <DReorderableList
            class="doc-category-index-editor__sections"
            @controls="manual"
            @disabled={{this.batchMode}}
            @group={{reorderGroup}}
            @items={{this.sections}}
            @itemTag="div"
            @label={{this.sectionLabel}}
            @listId={{ROOT_LIST}}
            @onRemove={{this.removeSection}}
            @rowClass="doc-category-index-editor__section-row"
            @tag="div"
          >
            <:empty>
              <DEmptyState
                @body={{i18n
                  "doc_categories.category_settings.index_editor.empty"
                }}
              />
            </:empty>
            <:row as |section controls|>
              <SectionRow
                @categoryId={{@categoryId}}
                @controls={{controls}}
                @editor={{this}}
                @group={{reorderGroup}}
                @section={{section}}
              />
            </:row>
          </DReorderableList>
        {{/let}}
      </DReorderableListGroup>

      <DConditionalInElement
        @append={{true}}
        @element={{@footerElement}}
        @inline={{not @footerElement}}
      >
        {{#unless this.batchMode}}
          <div class="doc-category-index-editor__footer">
            <DComboButton @hasMenu={{not this.hasAutoIndexSection}}>
              <:default as |combo|>
                <combo.Button
                  class="btn-default btn-small"
                  @action={{fn this.addSection null}}
                  @disabled={{this.sectionLimitReached}}
                  @icon="plus"
                  @label="doc_categories.category_settings.index_editor.add_section"
                />
                {{! The menu is gated by @hasMenu, so guarding it here as well
                    would be the same condition written twice. }}
                <combo.Menu
                  class="btn-default btn-small"
                  @identifier="add-section-menu"
                >
                  <DDropdownMenu as |dropdown|>
                    <dropdown.item>
                      <DButton
                        class="btn-transparent"
                        @action={{this.addAutoIndexSection}}
                        @disabled={{this.sectionLimitReached}}
                        @icon="bolt"
                        @label="doc_categories.category_settings.index_editor.add_auto_index_section"
                      />
                    </dropdown.item>
                  </DDropdownMenu>
                </combo.Menu>
              </:default>
            </DComboButton>
            {{#if this.sectionLimitReached}}
              <span class="doc-category-index-editor__capacity-message">
                {{this.sectionLimitMessage}}
              </span>
            {{/if}}
          </div>
        {{/unless}}

        <div class="doc-category-index-editor__apply-footer">
          <DButton
            class="btn-primary btn-small doc-category-index-editor__apply-btn"
            @action={{this.apply}}
            @disabled={{this.applyDisabled}}
            @icon="check"
            @label={{this.applyLabel}}
          />
        </div>
      </DConditionalInElement>
    </div>
  </template>
}
