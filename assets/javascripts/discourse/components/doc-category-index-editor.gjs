import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import {
  trackedArray,
  trackedObject,
  trackedSet,
} from "@ember/reactive/collections";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import DButton from "discourse/components/d-button";
import DComboButton from "discourse/components/d-combo-button";
import DIconGridPicker from "discourse/components/d-icon-grid-picker";
import DropdownMenu from "discourse/components/dropdown-menu";
import DMenu from "discourse/float-kit/components/d-menu";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { bind } from "discourse/lib/decorators";
import discourseLater from "discourse/lib/later";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { and, eq, not, or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

const autoFocus = modifier((element) => {
  element.focus();
  element.select();
});

/* Draggable link row with view/edit mode */
class IndexEditorLink extends Component {
  @service site;

  @tracked dragCssClass;
  @tracked editing = false;
  @tracked swapping = false;
  @tracked swapTopicContent = [];
  @tracked validationError = null;
  dragCount = 0;
  @tracked _editTitle;
  @tracked _editHref;
  @tracked _editIcon;
  @tracked _editType;
  @tracked _editTopicId;

  _isNew = false;

  constructor() {
    super(...arguments);
    /* New empty links auto-enter edit mode */
    if (!this.args.link.title && !this.args.link.href) {
      this._isNew = true;
      this._snapshotLink();
      this.editing = true;
    }
  }

  _snapshotLink() {
    this._editTitle = this.args.link.title;
    this._editHref = this.args.link.href;
    this._editIcon = this.args.link.icon;
    this._editType = this.args.link.type;
    this._editTopicId = this.args.link.topic_id;
    this._topicOriginalTitle = this.args.link.topicTitle;
  }

  _applyEdit() {
    const isTopicLink = this._editType === "topic";
    const titleMatchesTopic =
      isTopicLink &&
      (!this._editTitle?.trim() ||
        this._editTitle === this._topicOriginalTitle);

    this.args.link.title = titleMatchesTopic
      ? this._topicOriginalTitle
      : this._editTitle;
    this.args.link.href = this._editHref;
    this.args.link.icon = this._editIcon;
    this.args.link.type = this._editType;
    this.args.link.topic_id = this._editTopicId;
    this.args.link.topicTitle = this._topicOriginalTitle;
    this.args.link.autoTitle = titleMatchesTopic;
    this.args.onChange?.();
  }

  get isTopicLink() {
    if (this.editing) {
      return this._editType === "topic";
    }
    return this.args.link.type === "topic";
  }

  @action
  switchToManualLink() {
    this._editType = "manual";
    this._editHref = "";
    this.swapping = false;
    this.swapTopicContent = [];
  }

  @action
  switchToTopicLink() {
    this._editType = "topic";
    this._editHref = "";
    this.swapping = true;
  }

  get isDuplicate() {
    return this.args.duplicateHrefs?.has(this.args.link.href);
  }

  get linkClasses() {
    const classes = ["doc-category-index-editor__link"];
    if (this.dragCssClass) {
      classes.push(this.dragCssClass);
    }
    if (this.isDuplicate) {
      classes.push("--duplicate");
    }
    return classes.join(" ");
  }

  get displayTitle() {
    return (
      this.args.link.title ||
      i18n(
        "doc_categories.category_settings.index_editor.link_title_placeholder"
      )
    );
  }

  isAboveElement(event) {
    event.preventDefault();
    const target = event.currentTarget;
    const domRect = target.getBoundingClientRect();
    return event.offsetY < domRect.height / 2;
  }

  get canConfirm() {
    return !!this._editHref;
  }

  @action
  enterEdit() {
    if (this.args.batchMode) {
      return;
    }
    this._snapshotLink();
    this.editing = true;
    this.args.onEditStateChange?.(true);
  }

  @action
  confirmEdit() {
    const error = this.#validateLink();
    if (error) {
      this.validationError = error;
      return;
    }
    this.validationError = null;
    this._applyEdit();
    this._isNew = false;
    this.editing = false;
    this.swapping = false;
    this.swapTopicContent = [];
    this.args.onEditStateChange?.(false);
  }

  #validateLink() {
    if (!this._editHref?.trim()) {
      return i18n(
        "doc_categories.category_settings.index_editor.validation_empty_link_url"
      );
    }
    if (!this._editTitle?.trim() && this._editType !== "topic") {
      return i18n(
        "doc_categories.category_settings.index_editor.validation_empty_link_title"
      );
    }
    return null;
  }

  @action
  cancelEdit() {
    this.validationError = null;
    if (this._isNew) {
      this.args.onEditStateChange?.(false);
      const idx = this.args.section.links.indexOf(this.args.link);
      if (idx !== -1) {
        this.args.section.links.splice(idx, 1);
      }
      this.args.onChange?.();
      return;
    }
    this.editing = false;
    this.swapping = false;
    this.swapTopicContent = [];
    this.args.onEditStateChange?.(false);
  }

  @action
  onCardFocusOut(event) {
    const card = event.currentTarget;
    requestAnimationFrame(() => {
      if (
        card.contains(document.activeElement) ||
        document.querySelector(
          ".fk-d-menu__content, .select-kit-body, .d-modal"
        )
      ) {
        return;
      }
      if (!this.canConfirm) {
        return;
      }
      this._applyEdit();
      this._isNew = false;
      this.editing = false;
      this.swapping = false;
      this.swapTopicContent = [];
      this.args.onEditStateChange?.(false);
    });
  }

  @action
  dragHasStarted(event) {
    event.stopPropagation();
    const row = event.target.closest(".doc-category-index-editor__link");
    if (row) {
      event.dataTransfer.setDragImage(row, 0, 0);
    }
    event.dataTransfer.effectAllowed = "move";
    this.args.onDragStart(this.args.link, this.args.section);
    this.dragCssClass = "dragging";
  }

  @action
  dragOver(event) {
    event.preventDefault();
    event.stopPropagation();
    if (this.dragCssClass === "dragging" || this.args.isDraggingSection) {
      return;
    }
    const isAbove = this.isAboveElement(event);
    this._isAbove = isAbove;
    this.dragCssClass = isAbove ? "drag-above" : "drag-below";
  }

  @action
  dragEnter(event) {
    event.stopPropagation();
    this.dragCount++;
  }

  @action
  dragLeave(event) {
    event.stopPropagation();
    this.dragCount--;
    if (
      this.dragCount === 0 &&
      (this.dragCssClass === "drag-above" || this.dragCssClass === "drag-below")
    ) {
      discourseLater(() => {
        this.dragCssClass = null;
      }, 10);
    }
  }

  @action
  dropItem(event) {
    event.stopPropagation();
    this.dragCount = 0;
    if (this.args.isBatchDraggingItems) {
      this.args.onBatchItemDrop(
        this.args.link,
        this.args.section,
        this._isAbove
      );
    } else {
      this.args.onDrop(this.args.link, this.args.section, this._isAbove);
    }
    this.dragCssClass = null;
  }

  @action
  dragEnd() {
    this.dragCount = 0;
    this.dragCssClass = null;
  }

  @action
  updateTitle(event) {
    this._editTitle = event.target.value;
  }

  @action
  updateHref(event) {
    this._editHref = event.target.value;
  }

  @action
  updateIcon(value) {
    this._editIcon = value;
  }

  @action
  startSwap() {
    this.swapping = true;
  }

  @action
  onSwapTopic(topicId, topic) {
    if (topic) {
      this._topicOriginalTitle = topic.title || topic.fancy_title;
      this._editTitle = this._topicOriginalTitle;
      this._editHref = `/t/${topic.slug}/${topic.id}`;
      this._editTopicId = topic.id;
    }
    this.swapping = false;
    this.swapTopicContent = [];
  }

  @action
  cancelSwap() {
    this.swapping = false;
    this.swapTopicContent = [];
  }

  @action
  onKeydown(event) {
    if (event.key === "Enter" && this.canConfirm) {
      event.preventDefault();
      this.confirmEdit();
    } else if (event.key === "Escape") {
      if (this.swapping) {
        this.cancelSwap();
      } else {
        this.cancelEdit();
      }
      event.stopPropagation();
    }
  }

  get searchFilters() {
    if (!this.args.categoryId) {
      return "in:title include:unlisted";
    }
    return `in:title include:unlisted category:=${this.args.categoryId}`;
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}

    <div
      {{on "dragover" this.dragOver}}
      {{on "dragenter" this.dragEnter}}
      {{on "dragleave" this.dragLeave}}
      {{on "dragend" this.dragEnd}}
      {{on "drop" this.dropItem}}
      {{on "keydown" this.onKeydown}}
      class={{this.linkClasses}}
    >
      {{#if @batchMode}}
        <label class="doc-category-index-editor__batch-checkbox">
          <input
            type="checkbox"
            checked={{@isSelected}}
            {{on "click" @onToggleSelection}}
          />
        </label>
      {{else if this.site.desktopView}}
        <span
          class="doc-category-index-editor__drag-handle"
          draggable="true"
          {{on "dragstart" this.dragHasStarted}}
        >
          {{icon "grip-lines"}}
        </span>
      {{/if}}

      {{#if this.isDuplicate}}
        <span
          class="doc-category-index-editor__duplicate-icon"
          title={{i18n
            "doc_categories.category_settings.index_editor.duplicate_warning"
          }}
        >
          {{icon "triangle-exclamation"}}
        </span>
      {{/if}}

      {{#if this.editing}}
        {{! Edit mode: expanded card with all fields }}
        <div
          class={{concatClass
            "doc-category-index-editor__link-card --editing"
            (if this.validationError "--error")
          }}
          {{on "focusout" this.onCardFocusOut}}
        >
          <div class="doc-category-index-editor__link-edit-row">
            <DIconGridPicker
              @value={{this._editIcon}}
              @onChange={{this.updateIcon}}
              @favorites={{@favoriteIcons}}
              @showSelectedName={{true}}
            />
            <input
              type="text"
              value={{this._editTitle}}
              placeholder={{or
                this._topicOriginalTitle
                (i18n
                  "doc_categories.category_settings.index_editor.link_title_placeholder"
                )
              }}
              class="doc-category-index-editor__link-title"
              {{autoFocus}}
              {{on "input" this.updateTitle}}
            />
          </div>

          {{#if this.validationError}}
            <div class="doc-category-index-editor__validation-error">
              {{icon "triangle-exclamation"}}
              {{this.validationError}}
            </div>
          {{/if}}

          <div class="doc-category-index-editor__link-edit-row">
            {{#if this.isTopicLink}}
              {{#if this.swapping}}
                <div class="doc-category-index-editor__swap-chooser">
                  <TopicChooser
                    @value={{null}}
                    @content={{this.swapTopicContent}}
                    @onChange={{this.onSwapTopic}}
                    @options={{hash
                      additionalFilters=this.searchFilters
                      none="doc_categories.category_settings.index_editor.select_topic"
                    }}
                  />
                  <DButton
                    @icon="xmark"
                    @action={{this.cancelSwap}}
                    class="btn-flat btn-small"
                  />
                </div>
              {{else}}
                <span
                  class="doc-category-index-editor__link-topic-href --readonly"
                >
                  {{this._editHref}}
                </span>
                <DButton
                  @icon="arrows-rotate"
                  @action={{this.startSwap}}
                  @label="doc_categories.category_settings.index_editor.replace_topic"
                  class="btn-flat btn-small"
                />
              {{/if}}
            {{else}}
              <input
                type="text"
                value={{this._editHref}}
                placeholder={{i18n
                  "doc_categories.category_settings.index_editor.link_url_placeholder"
                }}
                class="doc-category-index-editor__link-url"
                {{on "input" this.updateHref}}
              />
            {{/if}}
          </div>

          <div class="doc-category-index-editor__link-edit-actions">
            {{#if this.isTopicLink}}
              <DButton
                @icon="link"
                @action={{this.switchToManualLink}}
                @label="doc_categories.category_settings.index_editor.switch_to_url"
                class="btn-flat btn-small"
              />
            {{else}}
              <DButton
                @icon="file"
                @action={{this.switchToTopicLink}}
                @label="doc_categories.category_settings.index_editor.switch_to_topic"
                class="btn-flat btn-small"
              />
            {{/if}}
            <DButton
              @icon="check"
              @action={{this.confirmEdit}}
              @disabled={{not this.canConfirm}}
              @title="doc_categories.category_settings.index_editor.confirm_edit"
              class="btn-flat btn-small doc-category-index-editor__confirm-edit-btn"
            />
            <DButton
              @icon="xmark"
              @action={{this.cancelEdit}}
              @title="cancel"
              class="btn-flat btn-small doc-category-index-editor__cancel-edit-btn"
            />
          </div>
        </div>
      {{else}}
        {{! View mode: card/pill with text labels }}
        {{! template-lint-disable no-invalid-interactive }}
        <div
          class={{concatClass
            "doc-category-index-editor__link-card"
            (if @isSelected "--selected")
          }}
          {{on "dblclick" this.enterEdit}}
        >
          <div class="doc-category-index-editor__link-card-header">
            <span class="doc-category-index-editor__link-icon">
              {{icon (or @link.icon "far-file")}}
            </span>
            <span
              class={{concatClass
                "doc-category-index-editor__link-label"
                (unless @link.title "--placeholder")
              }}
            >
              {{this.displayTitle}}
            </span>
            {{#if @link.autoTitle}}
              <span class="doc-category-index-editor__auto-badge">{{i18n
                  "doc_categories.category_settings.index_editor.auto_title"
                }}</span>
            {{/if}}
            {{#unless @batchMode}}
              <DButton
                @icon="pencil"
                @action={{this.enterEdit}}
                @title="doc_categories.category_settings.index_editor.edit_link"
                class="btn-flat btn-small doc-category-index-editor__edit-btn"
              />
              <DButton
                @icon="trash-can"
                @action={{fn @onRemove @link}}
                @title="doc_categories.category_settings.index_editor.remove_link"
                class="btn-flat btn-small doc-category-index-editor__remove-btn"
              />
            {{/unless}}
          </div>
          {{#if @link.href}}
            <span class="doc-category-index-editor__link-href-preview">
              {{@link.href}}
            </span>
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}

/* Draggable, collapsible section */
class IndexEditorSection extends Component {
  @service dialog;
  @service site;

  @tracked dragCssClass;
  @tracked emptyDropTarget = false;
  @tracked collapsed = false;
  @tracked editingTitle = false;
  @tracked titleValidationError = null;
  @tracked includeSubcategories = false;
  @tracked showingTopicChooser = false;
  @tracked topicChooserContent = [];
  dragCount = 0;

  _addMenuApi = null;

  @tracked _editSectionTitle;

  _autoExpandTimer = null;
  _isNew = false;

  constructor() {
    super(...arguments);
    /* New sections with empty title auto-enter title edit mode */
    if (!this.args.section.title) {
      this._isNew = true;
      this._editSectionTitle = "";
      this.editingTitle = true;
    }
  }

  get linkCount() {
    return this.args.section.links.length;
  }

  get hasDuplicateLinks() {
    return this.args.section.links.some((link) =>
      this.args.duplicateHrefs?.has(link.href)
    );
  }

  get isDuplicateTitle() {
    return this.args.duplicateTitles?.has(
      this.args.section.title?.toLowerCase()
    );
  }

  get displayTitle() {
    return (
      this.args.section.title ||
      i18n(
        "doc_categories.category_settings.index_editor.section_title_placeholder"
      )
    );
  }

  @action
  enterTitleEdit() {
    this._editSectionTitle = this.args.section.title;
    this.editingTitle = true;
    this.args.onEditStateChange?.(true);
  }

  @action
  confirmTitleEdit() {
    if (!this._editSectionTitle?.trim()) {
      this.titleValidationError = i18n(
        "doc_categories.category_settings.index_editor.validation_empty_section_title"
      );
      return;
    }
    this.titleValidationError = null;
    this.args.section.title = this._editSectionTitle;
    this.args.onChange?.();
    this._isNew = false;
    this.editingTitle = false;
    this.args.onEditStateChange?.(false);
  }

  @action
  cancelTitleEdit() {
    this.titleValidationError = null;
    if (this._isNew) {
      this.args.onEditStateChange?.(false);
      this.args.onCancelNew?.(this.args.section);
      return;
    }
    this.editingTitle = false;
    this.args.onEditStateChange?.(false);
  }

  @action
  onTitleKeydown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      this.confirmTitleEdit();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.cancelTitleEdit();
    }
  }

  isAboveElement(event) {
    event.preventDefault();
    const target = event.currentTarget;
    const domRect = target.getBoundingClientRect();
    return event.offsetY < domRect.height / 2;
  }

  @action
  toggleCollapsed() {
    this.collapsed = !this.collapsed;
  }

  @action
  sectionDragHasStarted(event) {
    const section = event.target.closest(
      ".doc-category-index-editor__section-row"
    );
    if (section) {
      event.dataTransfer.setDragImage(section, 0, 0);
    }
    event.dataTransfer.effectAllowed = "move";
    this.args.onSectionDragStart(this.args.section);
    this.dragCssClass = "dragging";
  }

  get #isEmptyItemDrag() {
    if (this.args.section.links.length > 0) {
      return false;
    }
    return (
      !this.args.isDraggingSection &&
      !(this.args.isBatchDragging && this.args.batchDragType === "sections")
    );
  }

  @action
  sectionDragOver(event) {
    event.preventDefault();
    if (this.dragCssClass === "dragging") {
      return;
    }
    const isBatchSectionDrag =
      this.args.isBatchDragging && this.args.batchDragType === "sections";
    if (this.args.isDraggingSection || isBatchSectionDrag) {
      this.dragCssClass = this.isAboveElement(event)
        ? "drag-above"
        : "drag-below";
    }
  }

  @action
  sectionDragEnter() {
    this.dragCount++;
    if (this.collapsed) {
      this._autoExpandTimer = discourseLater(() => {
        this.collapsed = false;
      }, 500);
    }
    if (this.#isEmptyItemDrag) {
      this.emptyDropTarget = true;
    }
  }

  @action
  sectionDragLeave() {
    this.dragCount--;
    if (this._autoExpandTimer && this.dragCount === 0) {
      clearTimeout(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
    if (this.dragCount === 0) {
      this.emptyDropTarget = false;
      if (
        this.dragCssClass === "drag-above" ||
        this.dragCssClass === "drag-below"
      ) {
        discourseLater(() => {
          this.dragCssClass = null;
        }, 10);
      }
    }
  }

  @action
  sectionDropItem(event) {
    event.stopPropagation();
    this.dragCount = 0;
    if (this._autoExpandTimer) {
      clearTimeout(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }

    const hasIndicator =
      this.dragCssClass === "drag-above" ||
      this.dragCssClass === "drag-below" ||
      this.emptyDropTarget;

    if (!hasIndicator) {
      this.dragCssClass = null;
      this.emptyDropTarget = false;
      return;
    }

    const isAbove = this.isAboveElement(event);
    if (this.args.isBatchDragging && this.args.batchDragType === "sections") {
      this.args.onBatchSectionDrop(this.args.section, isAbove);
    } else if (this.emptyDropTarget) {
      if (this.args.isBatchDragging && this.args.batchDragType === "items") {
        this.args.onBatchItemDrop(null, this.args.section, false);
      } else {
        this.args.onSectionDrop(this.args.section, isAbove);
      }
    } else {
      this.args.onSectionDrop(this.args.section, isAbove);
    }
    this.dragCssClass = null;
    this.emptyDropTarget = false;
  }

  @action
  sectionDragEnd() {
    this.dragCount = 0;
    this.dragCssClass = null;
    this.emptyDropTarget = false;
    this.args.onSectionDragEnd?.();
    if (this._autoExpandTimer) {
      clearTimeout(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
  }

  @action
  updateTitle(event) {
    this._editSectionTitle = event.target.value;
  }

  @action
  registerAddMenuApi(api) {
    this._addMenuApi = api;
  }

  @action
  addManualLink() {
    this.args.section.links.push(
      trackedObject({ title: "", href: "", type: "manual", icon: "link" })
    );
    this.collapsed = false;
    this.args.onChange?.();
  }

  @action
  showTopicChooser() {
    this.showingTopicChooser = true;
    this.collapsed = false;
  }

  @action
  toggleIncludeSubcategories() {
    this.includeSubcategories = !this.includeSubcategories;
  }

  @action
  async addMissingTopicsToSection() {
    this._addMenuApi?.close();
    const includeSubcategories = this.includeSubcategories;
    try {
      const topics = await this.args.fetchTopics(includeSubcategories);
      if (topics.length === 0) {
        this.dialog.alert(
          i18n("doc_categories.category_settings.index_editor.no_topics_found")
        );
        return;
      }
      const existingHrefs = new Set(
        this.args.section.links.map((link) => link.href).filter(Boolean)
      );
      const missing = topics.filter(
        (t) => !existingHrefs.has(`/t/${t.slug}/${t.id}`)
      );
      if (missing.length === 0) {
        this.dialog.alert(
          i18n(
            "doc_categories.category_settings.index_editor.no_missing_topics"
          )
        );
        return;
      }
      for (const topic of missing) {
        this.args.section.links.push(
          trackedObject({
            title: topic.title || topic.fancy_title,
            href: `/t/${topic.slug}/${topic.id}`,
            type: "topic",
            icon: "far-file",
          })
        );
      }
      this.collapsed = false;
      this.args.onChange?.();
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  onAddTopic(topicId, topic) {
    if (!topic) {
      return;
    }
    const topicTitle = topic.title || topic.fancy_title;
    this.args.section.links.push(
      trackedObject({
        title: topicTitle,
        href: `/t/${topic.slug}/${topic.id}`,
        type: "topic",
        topic_id: topic.id,
        topicTitle,
        autoTitle: true,
        icon: "far-file",
      })
    );
    this.topicChooserContent = [];
    this.showingTopicChooser = false;
    this.args.onChange?.();
  }

  @action
  cancelTopicChooser() {
    this.showingTopicChooser = false;
  }

  @action
  removeLink(link) {
    this.dialog.yesNoConfirm({
      message: i18n(
        "doc_categories.category_settings.index_editor.confirm_remove_link"
      ),
      didConfirm: () => {
        const idx = this.args.section.links.indexOf(link);
        if (idx !== -1) {
          this.args.section.links.splice(idx, 1);
        }
        this.args.onChange?.();
      },
    });
  }

  get searchFilters() {
    if (!this.args.categoryId) {
      return "in:title include:unlisted";
    }
    return `in:title include:unlisted category:=${this.args.categoryId}`;
  }

  <template>
    {{! template-lint-disable no-invalid-interactive }}

    <div
      {{on "dragover" this.sectionDragOver}}
      {{on "dragenter" this.sectionDragEnter}}
      {{on "dragleave" this.sectionDragLeave}}
      {{on "dragend" this.sectionDragEnd}}
      {{on "drop" this.sectionDropItem}}
      class={{concatClass
        "doc-category-index-editor__section-row"
        this.dragCssClass
      }}
    >
      {{#if @batchMode}}
        <label class="doc-category-index-editor__batch-checkbox">
          <input
            type="checkbox"
            checked={{@isSectionSelected @section}}
            {{on "click" (fn @toggleSectionSelection @section)}}
          />
        </label>
      {{else if this.site.desktopView}}
        <span
          class="doc-category-index-editor__drag-handle"
          draggable="true"
          {{on "dragstart" this.sectionDragHasStarted}}
        >
          {{icon "grip-lines"}}
        </span>
      {{/if}}

      <div
        class={{concatClass
          "doc-category-index-editor__section"
          (if (@isSectionSelected @section) "--selected")
          (if this.titleValidationError "--error")
        }}
      >
        <div class="doc-category-index-editor__section-header">
          <DButton
            @icon={{if this.collapsed "angle-right" "angle-down"}}
            @action={{this.toggleCollapsed}}
            class="btn-flat btn-small doc-category-index-editor__collapse-btn"
          />

          {{#if this.editingTitle}}
            <input
              type="text"
              value={{this._editSectionTitle}}
              placeholder={{i18n
                "doc_categories.category_settings.index_editor.section_title_placeholder"
              }}
              class="doc-category-index-editor__section-title"
              {{autoFocus}}
              {{on "input" this.updateTitle}}
              {{on "keydown" this.onTitleKeydown}}
            />
            <DButton
              @icon="check"
              @action={{this.confirmTitleEdit}}
              @title="doc_categories.category_settings.index_editor.confirm_edit"
              class="btn-flat btn-small doc-category-index-editor__confirm-title-btn"
            />
            <DButton
              @icon="xmark"
              @action={{this.cancelTitleEdit}}
              @title="cancel"
              class="btn-flat btn-small doc-category-index-editor__cancel-title-btn"
            />
          {{else}}
            {{! template-lint-disable no-invalid-interactive }}
            <span
              class={{concatClass
                "doc-category-index-editor__section-title-label"
                (unless @section.title "--placeholder")
              }}
              {{on "dblclick" this.enterTitleEdit}}
            >
              {{this.displayTitle}}
            </span>
          {{/if}}

          {{#if this.isDuplicateTitle}}
            <span
              class="doc-category-index-editor__duplicate-icon"
              title={{i18n
                "doc_categories.category_settings.index_editor.duplicate_title_warning"
              }}
            >
              {{icon "triangle-exclamation"}}
            </span>
          {{/if}}

          {{#if this.collapsed}}
            {{#if this.hasDuplicateLinks}}
              <span
                class="doc-category-index-editor__duplicate-icon"
                title={{i18n
                  "doc_categories.category_settings.index_editor.duplicate_warning"
                }}
              >
                {{icon "triangle-exclamation"}}
              </span>
            {{/if}}
            <span class="doc-category-index-editor__link-count">
              {{this.linkCount}}
            </span>
          {{/if}}

          {{#if @batchMode}}
            <DButton
              @icon="check-double"
              @action={{fn @selectAllInSection @section}}
              @title="doc_categories.category_settings.index_editor.batch_select_all"
              class="btn-flat btn-small"
            />
            <DButton
              @icon="right-left"
              @action={{fn @invertSelectionInSection @section}}
              @title="doc_categories.category_settings.index_editor.batch_invert"
              class="btn-flat btn-small"
            />
            <DButton
              @icon="eraser"
              @action={{fn @clearAllInSection @section}}
              @title="doc_categories.category_settings.index_editor.batch_clear_all"
              class="btn-flat btn-small"
            />
          {{else}}{{#unless this.editingTitle}}
              <DButton
                @icon="pencil"
                @action={{this.enterTitleEdit}}
                @title="doc_categories.category_settings.index_editor.edit_section_title"
                class="btn-flat btn-small doc-category-index-editor__edit-btn"
              />
              <DButton
                @icon="trash-can"
                @action={{fn @onRemove @section}}
                @title="doc_categories.category_settings.index_editor.remove_section"
                class="btn-flat btn-small doc-category-index-editor__remove-btn"
              />
            {{/unless}}{{/if}}
        </div>

        {{#if this.titleValidationError}}
          <div class="doc-category-index-editor__validation-error">
            {{icon "triangle-exclamation"}}
            {{this.titleValidationError}}
          </div>
        {{/if}}

        <div
          class={{concatClass
            "doc-category-index-editor__section-body"
            (if this.collapsed "--collapsed")
            (if this.emptyDropTarget "--drop-target")
          }}
        >
          {{#unless this.collapsed}}
            <div class="doc-category-index-editor__links">
              {{#each @section.links as |link|}}
                <IndexEditorLink
                  @link={{link}}
                  @section={{@section}}
                  @categoryId={{@categoryId}}
                  @duplicateHrefs={{@duplicateHrefs}}
                  @favoriteIcons={{@favoriteIcons}}
                  @batchMode={{@batchMode}}
                  @isBatchDraggingItems={{and
                    @isBatchDragging
                    (eq @batchDragType "items")
                  }}
                  @isDraggingSection={{or
                    @isDraggingSection
                    (and @isBatchDragging (eq @batchDragType "sections"))
                  }}
                  @isSelected={{@isItemSelected link}}
                  @onToggleSelection={{fn @toggleItemSelection link}}
                  @onEditStateChange={{@onEditStateChange}}
                  @onRemove={{this.removeLink}}
                  @onDragStart={{@onLinkDragStart}}
                  @onDrop={{@onLinkDrop}}
                  @onBatchItemDrop={{@onBatchItemDrop}}
                  @onChange={{@onChange}}
                />
              {{/each}}
            </div>

            {{#if (and this.showingTopicChooser (not @batchMode))}}
              <div class="doc-category-index-editor__inline-topic-chooser">
                <div class="doc-category-index-editor__link-card --adding">
                  <TopicChooser
                    @value={{null}}
                    @content={{this.topicChooserContent}}
                    @onChange={{this.onAddTopic}}
                    @options={{hash
                      additionalFilters=this.searchFilters
                      none="doc_categories.category_settings.index_editor.select_topic"
                    }}
                  />
                  <DButton
                    @icon="xmark"
                    @action={{this.cancelTopicChooser}}
                    class="btn-flat btn-small"
                  />
                </div>
              </div>
            {{/if}}

            {{#unless @batchMode}}
              <div class="doc-category-index-editor__section-actions">
                <DComboButton class="--has-menu btn-small">
                  <:default as |combo|>
                    <combo.Button
                      @action={{this.showTopicChooser}}
                      @icon="plus"
                      @label="doc_categories.category_settings.index_editor.add_topic"
                    />
                    <combo.Menu
                      @identifier="section-add-menu"
                      @onRegisterApi={{this.registerAddMenuApi}}
                    >
                      <DropdownMenu as |dropdown|>
                        <dropdown.item>
                          <DButton
                            @icon="link"
                            @label="doc_categories.category_settings.index_editor.add_link"
                            @action={{this.addManualLink}}
                            class="btn-transparent"
                          />
                        </dropdown.item>
                        <dropdown.divider />
                        <dropdown.item>
                          <DButton
                            @icon="list-check"
                            @label="doc_categories.category_settings.index_editor.add_missing_topics_to_section"
                            @action={{this.addMissingTopicsToSection}}
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
                      </DropdownMenu>
                    </combo.Menu>
                  </:default>
                </DComboButton>
              </div>
            {{/unless}}
          {{/unless}}
        </div>
      </div>
    </div>
  </template>
}

/* Main index editor */
export default class DocCategoryIndexEditor extends Component {
  @service dialog;

  @tracked sections = trackedArray(this.initSections());
  @tracked saveState = null;
  @tracked includeSubcategories = false;
  @tracked isDraggingSection = false;
  @tracked batchMode = false;
  @tracked editingCount = 0;
  @tracked isBatchDragging = false;
  @tracked batchDragType = null;
  selectedItems = trackedSet();
  selectedSections = trackedSet();
  draggedSection = null;
  _draggedLink = null;
  _draggedLinkSourceSection = null;

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
    // Only persist editor state if the mode is still "direct" (topic_id === -1).
    // When switching to "none" mode, #applyNoneMode() already set the correct
    // form values -- overwriting them here would send stale data to the backend.
    if (this.args.form?.get("doc_index_topic_id") === -1) {
      this._saveToTransientData();
    }
  }

  get serializedSections() {
    const serialized = this._serializeSections();
    return serialized.length > 0 ? JSON.stringify(serialized) : null;
  }

  initSections() {
    /* Restore from FormKit transient data if available (tab switch recovery) */
    const saved = this.args.transientData?._docIndexSections;
    if (saved?.length > 0) {
      return saved.map((section) =>
        trackedObject({
          title: section.title,
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
              })
            )
          ),
        })
      );
    }

    return this._initSectionsFromModel();
  }

  _initSectionsFromModel() {
    const index = this.args.indexData;
    if (!index || index.length === 0) {
      return [];
    }
    return index.map((section) =>
      trackedObject({
        title: section.text,
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
            })
          )
        ),
      })
    );
  }

  _serializeSections() {
    return this.sections.map((section) => ({
      title: section.title,
      links: section.links.map((link) => ({
        title: link.title,
        href: link.href,
        type: link.type,
        topic_id: link.topic_id,
        topicTitle: link.topicTitle,
        autoTitle: link.autoTitle,
        icon: link.icon,
      })),
    }));
  }

  @bind
  _saveToTransientData() {
    const sections = this._serializeSections();
    this.args.form?.set("_docIndexSections", sections);

    // Keep FormKit form data in sync so the save payload is correct
    const serialized = sections.length > 0 ? JSON.stringify(sections) : null;
    this.args.form?.set("doc_index_sections", serialized);
    if (serialized) {
      this.args.form?.set("doc_index_topic_id", -1);
    }
  }

  get isEmpty() {
    return this.sections.length === 0;
  }

  get validationErrors() {
    const errors = [];

    if (this.editingCount > 0) {
      errors.push(
        i18n(
          "doc_categories.category_settings.index_editor.validation_pending_changes"
        )
      );
    }

    for (const section of this.sections) {
      if (!section.title?.trim()) {
        errors.push(
          i18n(
            "doc_categories.category_settings.index_editor.validation_empty_section_title"
          )
        );
      }
      if (section.links.length === 0) {
        errors.push(
          i18n(
            "doc_categories.category_settings.index_editor.validation_empty_section"
          )
        );
      }
      for (const link of section.links) {
        if (!link.title?.trim() && link.type !== "topic") {
          errors.push(
            i18n(
              "doc_categories.category_settings.index_editor.validation_empty_link_title"
            )
          );
        }
        if (!link.href?.trim()) {
          errors.push(
            i18n(
              "doc_categories.category_settings.index_editor.validation_empty_link_url"
            )
          );
        }
      }
    }

    return errors;
  }

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
  cancelNewSection(section) {
    const idx = this.sections.indexOf(section);
    if (idx !== -1) {
      this.sections.splice(idx, 1);
    }
    this._saveToTransientData();
  }

  @action
  removeSection(section) {
    this.dialog.yesNoConfirm({
      message: i18n(
        "doc_categories.category_settings.index_editor.confirm_remove_section"
      ),
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
  @action
  setDraggedSection(section) {
    this.draggedSection = section;
    this.isDraggingSection = true;
  }

  @action
  clearDraggedSection() {
    this.draggedSection = null;
    this.isDraggingSection = false;
  }

  @action
  reorderSection(targetSection, isAbove) {
    /* Handle link dropped on section body (not on a specific link) */
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
  @action
  onLinkDragStart(link, sourceSection) {
    this._draggedLink = link;
    this._draggedLinkSourceSection = sourceSection;
  }

  @action
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
    return response.topics || [];
  }

  async _fetchCategoryTopics() {
    return this.fetchTopics(this.includeSubcategories);
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
      const topics = await this._fetchCategoryTopics();
      if (topics.length === 0) {
        return;
      }
      this.sections.splice(
        0,
        this.sections.length,
        trackedObject({
          title: i18n(
            "doc_categories.category_settings.index_editor.all_topics_section"
          ),
          links: trackedArray(topics.map((t) => this._topicToLink(t))),
        })
      );
      this._saveToTransientData();
    } catch (e) {
      popupAjaxError(e);
    }
  }

  /* Apply (saves doc-index only, without saving category) */
  @action
  async apply() {
    if (this.validationErrors.length > 0) {
      this.saveState = "error";
      return;
    }
    this.saveState = "saving";
    const payload = {
      sections: this.sections.map((section) => ({
        title: section.title,
        links: section.links.map((link) => ({
          title: link.title,
          href: link.href,
          type: link.type,
          topic_id: link.topic_id,
          icon: link.icon,
        })),
      })),
    };

    try {
      await ajax(`/doc-categories/indexes/${this.args.categoryId}`, {
        type: "PUT",
        data: JSON.stringify(payload),
        contentType: "application/json",
      });
      this.saveState = "saved";
      this.args.form?.set("_docIndexSections", null);
      this.args.form?.commitField("_docIndexSections");
      this.args.category?.set("doc_index_sections", null);
      discourseLater(() => {
        if (this.saveState === "saved") {
          this.saveState = null;
        }
      }, 3000);
    } catch (e) {
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
    return this.args.transientData?._docIndexSections != null;
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
    this.batchMode = !this.batchMode;
    if (!this.batchMode) {
      this.selectedItems.clear();
      this.selectedSections.clear();
    }
  }

  @action
  onEditStateChange(isEditing) {
    this.editingCount += isEditing ? 1 : -1;
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

  @action
  clearSelection() {
    this.selectedItems.clear();
    this.selectedSections.clear();
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

  @action
  batchReorderSections(targetSection, isAbove) {
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

  @action
  batchReorderItems(targetLink, targetSection, isAbove) {
    /* Collect selected items preserving their current order across all sections */
    const ordered = [];
    for (const section of this.sections) {
      for (const link of section.links) {
        if (this.selectedItems.has(link)) {
          ordered.push(link);
        }
      }
    }

    /* Remove selected items from their source sections */
    for (const link of ordered) {
      for (const section of this.sections) {
        const idx = section.links.indexOf(link);
        if (idx !== -1) {
          section.links.splice(idx, 1);
          break;
        }
      }
    }

    /* Insert at target position (append to end if dropped on section body) */
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
    return this.saveState === "saving" || !this.hasPendingChanges;
  }

  <template>
    <div
      class={{concatClass
        "doc-category-index-editor"
        (if this.batchMode "--batch-mode")
      }}
    >
      {{#if @toolbarElement}}
        {{#in-element @toolbarElement insertBefore=null}}
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
                        class="btn-transparent btn-danger"
                      />
                    </dropdown.item>
                  </DropdownMenu>
                </:content>
              </DMenu>
            </div>
          {{/unless}}
        {{/in-element}}
      {{/if}}

      {{#if this.batchMode}}
        <div class="doc-category-index-editor__batch-bar">
          {{#if this.canDragSelection}}
            <span
              class="doc-category-index-editor__batch-drag-handle"
              draggable="true"
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

          {{#if this.hasSelection}}
            <DButton
              @icon="eraser"
              @label="doc_categories.category_settings.index_editor.batch_clear_all"
              @action={{this.clearSelection}}
              class="btn-flat btn-small"
            />
            <DButton
              @icon="trash-can"
              @action={{this.bulkDelete}}
              class="btn-flat btn-small doc-category-index-editor__batch-delete-btn"
            />
          {{/if}}

          <DButton
            @icon="xmark"
            @action={{this.toggleBatchMode}}
            class="btn-flat btn-small doc-category-index-editor__batch-cancel-btn"
          />
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
            @categoryId={{@categoryId}}
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
            @onChange={{this._saveToTransientData}}
          />
        {{/each}}
      </div>

      {{#unless this.batchMode}}
        <div class="doc-category-index-editor__footer">
          <DButton
            @icon="plus"
            @label="doc_categories.category_settings.index_editor.add_section"
            @action={{this.addSection}}
            class="btn-default btn-small"
          />
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
    </div>
  </template>
}
