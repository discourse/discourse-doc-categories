import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { not, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DIconGridPicker from "discourse/ui-kit/d-icon-grid-picker";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import icon from "discourse/ui-kit/helpers/d-icon";
import dAutoFocus from "discourse/ui-kit/modifiers/d-auto-focus";
import dDragAndDropTarget from "discourse/ui-kit/modifiers/d-drag-and-drop-target";
import { i18n } from "discourse-i18n";

/** What a dragged batch selection of links publishes. */
export const LINK_DRAG_TYPE = "doc-index-link";

// Selectors for floating/overlay elements that steal focus from the card.
// When one of these is open, focusout should not auto-confirm the edit.
const FLOATING_ELEMENT_SELECTOR =
  ".fk-d-menu__content, .select-kit-body, .d-modal";

export class IndexEditorLink extends Component {
  @tracked swapping = false;
  @tracked swapTopicContent = [];
  @tracked validationError = null;

  #isNew = false;

  @tracked _editTitle;
  @tracked _editHref;
  @tracked _editIcon;
  @tracked _editType;
  @tracked _editTopicId;
  @tracked _topicOriginalTitle = null;

  constructor() {
    super(...arguments);
    // New empty links auto-enter edit mode
    if (this.editing) {
      this.#isNew = true;
      this.#snapshotLink();
    }
  }

  get editing() {
    return !!this.args.link.isEditing;
  }

  set editing(value) {
    this.args.link.isEditing = value;
  }

  get isTopicLink() {
    if (this.editing) {
      return this._editType === "topic";
    }
    return this.args.link.type === "topic";
  }

  get isDuplicate() {
    return this.args.duplicateHrefs?.has(this.args.link.href);
  }

  get displayTitle() {
    return (
      this.args.link.title ||
      i18n(
        "doc_categories.category_settings.index_editor.link_title_placeholder"
      )
    );
  }

  get canConfirm() {
    return !!this._editHref;
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

  @action
  enterEdit() {
    if (this.args.batchMode) {
      return;
    }
    this.#snapshotLink();
    this.editing = true;
  }

  @action
  confirmEdit() {
    const error = this.#validateLink();
    if (error) {
      this.validationError = error;
      return;
    }
    this.validationError = null;
    this.#applyEdit();
    this.#isNew = false;
    this.editing = false;
    this.swapping = false;
    this.swapTopicContent = [];
  }

  @action
  cancelEdit() {
    this.validationError = null;
    if (this.#isNew) {
      this.editing = false;
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
  }

  @action
  onCardFocusOut(event) {
    const card = event.currentTarget;

    next(() => {
      if (this.isDestroying || this.isDestroyed) {
        return;
      }

      if (
        card.contains(document.activeElement) ||
        document.querySelector(FLOATING_ELEMENT_SELECTOR)
      ) {
        return;
      }

      if (!this.canConfirm) {
        return;
      }

      const error = this.#validateLink();
      if (error) {
        this.validationError = error;
        return;
      }

      this.validationError = null;
      this.#applyEdit();
      this.#isNew = false;
      this.editing = false;
      this.swapping = false;
      this.swapTopicContent = [];
    });
  }

  /**
   * Where a batch selection landed. Only the batch path asks: an ordinary
   * reorder is the list's, and this row never sees it.
   */
  @action
  onBatchRowDrop({ position }) {
    this.args.onBatchItemDrop(
      this.args.link,
      this.args.section,
      position === "before"
    );
  }

  /** Whether a batch selection of links may land on this row. */
  @action
  canDropBatchLinks() {
    return !!this.args.isBatchDraggingItems;
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

  #snapshotLink() {
    this._editTitle = this.args.link.title;
    this._editHref = this.args.link.href;
    this._editIcon = this.args.link.icon;
    this._editType = this.args.link.type;
    this._editTopicId = this.args.link.topic_id;
    this._topicOriginalTitle = this.args.link.topicTitle;
  }

  #applyEdit() {
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

  <template>
    {{! The row element belongs to the list: it carries the drag registration,
        the class and the keyed identity, and this fills it. }}
    {{#if @batchMode}}
      <label class="doc-category-index-editor__batch-checkbox">
        <input
          type="checkbox"
          checked={{@isSelected}}
          {{on "click" @onToggleSelection}}
        />
      </label>
    {{else if @controls.handle}}
      {{! On every viewport, unlike the grip it replaces: it is the menu
          trigger and the keyboard path as well as the drag. }}
      <@controls.handle class="doc-category-index-editor__drag-handle" />
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
        class={{dConcatClass
          "doc-category-index-editor__link-card --editing"
          (if this.validationError "--error")
        }}
        {{on "focusout" this.onCardFocusOut}}
        {{on "keydown" this.onKeydown}}
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
            {{dAutoFocus selectText=true}}
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
                    additionalFilters=@searchFilters
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
      {{! Batch mode switches the list off, so its row registers no drop target
          and this carries one instead. Gated rather than conditional, since a
          re-curried modifier would re-register mid-drag. }}
      <div
        class={{dConcatClass
          "doc-category-index-editor__link-card"
          (if @isSelected "--selected")
        }}
        {{dDragAndDropTarget
          accepts=LINK_DRAG_TYPE
          acceptsSelf=false
          canDrop=this.canDropBatchLinks
          onDrop=this.onBatchRowDrop
        }}
        {{on "dblclick" this.enterEdit}}
      >
        <div class="doc-category-index-editor__link-card-header">
          <span class="doc-category-index-editor__link-icon">
            {{icon (or @link.icon "far-file")}}
          </span>
          <span
            class={{dConcatClass
              "doc-category-index-editor__link-label"
              (unless @link.title "--placeholder")
            }}
          >
            {{this.displayTitle}}
          </span>
          {{#if @link.autoIndexed}}
            <span class="doc-category-index-editor__item-badge">{{i18n
                "doc_categories.category_settings.index_editor.auto_indexed"
              }}</span>
          {{else if @link.autoTitle}}
            <span class="doc-category-index-editor__item-badge">{{i18n
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
            {{#if @controls.remove}}
              <@controls.remove
                class="btn-flat btn-small doc-category-index-editor__remove-btn"
              />
            {{/if}}
          {{/unless}}
        </div>
        {{#if @link.href}}
          <span class="doc-category-index-editor__link-href-preview">
            {{@link.href}}
          </span>
        {{/if}}
      </div>
    {{/if}}
  </template>
}
