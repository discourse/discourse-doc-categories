import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trackedObject } from "@ember/reactive/collections";
import { service } from "@ember/service";
import DMenu from "discourse/float-kit/components/d-menu";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { and, eq, not, or } from "discourse/truth-helpers";
import DButton from "discourse/ui-kit/d-button";
import DComboButton from "discourse/ui-kit/d-combo-button";
import DDropdownMenu from "discourse/ui-kit/d-dropdown-menu";
import DReorderableList from "discourse/ui-kit/d-reorderable-list";
import dConcatClass from "discourse/ui-kit/helpers/d-concat-class";
import icon from "discourse/ui-kit/helpers/d-icon";
import dAutoFocus from "discourse/ui-kit/modifiers/d-auto-focus";
import dDragAndDropTarget from "discourse/ui-kit/modifiers/d-drag-and-drop-target";
import dDragDwell from "discourse/ui-kit/modifiers/d-drag-dwell";
import { i18n } from "discourse-i18n";
import { MAX_LINKS_PER_SECTION } from "../../lib/constants.js";
import { IndexEditorLink, LINK_DRAG_TYPE } from "./link.gjs";

/** What a dragged batch selection of sections publishes. */
export const SECTION_DRAG_TYPE = "doc-index-section";

export class IndexEditorSection extends Component {
  @service dialog;

  @tracked titleValidationError = null;

  @tracked showingTopicChooser = false;

  @tracked topicChooserContent = [];

  #addMenuApi = null;

  #isNew = false;

  @tracked _editSectionTitle;

  constructor() {
    super(...arguments);
    // New sections with empty title auto-enter title edit mode,
    // but the first section is allowed to have an empty title
    if (this.editingTitle) {
      this.#isNew = !this.args.section.title;
      this._editSectionTitle = this.args.section.title || "";
    }
  }

  /**
   * Held on the section rather than here, so the editor can open one it has
   * just sent a link into. Never serialized: the writer names its fields.
   */
  get collapsed() {
    return !!this.args.section.collapsed;
  }

  set collapsed(value) {
    this.args.section.collapsed = value;
  }

  get editingTitle() {
    return !!this.args.section.isEditingTitle;
  }

  set editingTitle(value) {
    this.args.section.isEditingTitle = value;
  }

  get linkLimitReached() {
    return this.linkCount >= MAX_LINKS_PER_SECTION;
  }

  get linkLimitMessage() {
    return i18n("doc_categories.category_settings.index_editor.link_limit", {
      count: MAX_LINKS_PER_SECTION,
    });
  }

  get linkCount() {
    return this.args.section.links.length;
  }

  /**
   * Whether the section's body has to show a drop slot of its own. A section
   * with no links has no row to aim at, so the body is what a batch lands on,
   * and in batch mode the links list that would otherwise mark itself as an
   * empty drop target is switched off. Without a slot the body has no height,
   * leaving a live target nothing can be dropped onto.
   */
  get showsBatchDropSlot() {
    return (
      this.args.batchMode &&
      this.linkCount === 0 &&
      !this.args.section.autoIndex
    );
  }

  get hasDuplicateLinks() {
    return this.args.section.links.some((link) =>
      this.args.duplicateHrefs?.has(link.href)
    );
  }

  get isFirstSection() {
    return this.args.isFirstSection?.(this.args.section);
  }

  get missingTitleError() {
    if (
      this.editingTitle ||
      this.args.section.title?.trim() ||
      this.isFirstSection
    ) {
      return null;
    }
    return i18n(
      "doc_categories.category_settings.index_editor.validation_empty_section_title"
    );
  }

  get isDuplicateTitle() {
    return this.args.duplicateTitles?.has(
      this.args.section.title?.toLowerCase()
    );
  }

  get displayTitle() {
    if (this.args.section.title) {
      return this.args.section.title;
    }

    if (this.isFirstSection) {
      return i18n(
        "doc_categories.category_settings.index_editor.first_section_no_title"
      );
    }

    return i18n(
      "doc_categories.category_settings.index_editor.section_title_placeholder"
    );
  }

  @action
  enterTitleEdit() {
    this._editSectionTitle = this.args.section.title;
    this.editingTitle = true;
  }

  @action
  confirmTitleEdit() {
    if (!this._editSectionTitle?.trim() && !this.isFirstSection) {
      this.titleValidationError = i18n(
        "doc_categories.category_settings.index_editor.validation_empty_section_title"
      );
      return;
    }
    this.titleValidationError = null;
    this.args.section.title = this._editSectionTitle?.trim() || "";
    this.args.onChange?.();
    this.#isNew = false;
    this.editingTitle = false;
  }

  @action
  cancelTitleEdit() {
    this.titleValidationError = null;
    if (this.#isNew) {
      this.editingTitle = false;
      this.args.onCancelNew?.(this.args.section);
      return;
    }
    this.editingTitle = false;
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

  @action
  updateTitle(event) {
    this._editSectionTitle = event.target.value;
  }

  @action
  toggleCollapsed() {
    this.collapsed = !this.collapsed;
  }

  /**
   * Opens a collapsed section once a drag has dwelled over it, so its rows can
   * be aimed at. Never re-collapsed: the reader was heading in.
   */
  @action
  expandForDrag() {
    this.collapsed = false;
  }

  /** Whether a batch selection of sections may land on this one. */
  @action
  canDropBatchSections() {
    return this.args.batchMode && this.args.batchDragType === "sections";
  }

  /**
   * Whether a batch selection of links may land in this section's body. Only
   * the batch path asks: an ordinary link aims at a row, or at the links list
   * itself when the section has none.
   */
  @action
  canDropBatchLinks() {
    return this.args.batchMode && this.args.batchDragType === "items";
  }

  @action
  onBatchSectionDrop({ position }) {
    this.args.onBatchSectionDrop(this.args.section, position === "before");
  }

  @action
  onBatchLinkDrop() {
    this.args.onBatchItemDrop(null, this.args.section, false);
  }

  @action
  registerAddMenuApi(api) {
    this.#addMenuApi = api;
  }

  @action
  addManualLink() {
    if (this.linkLimitReached) {
      return;
    }
    this.args.section.links.push(
      trackedObject({
        title: "",
        href: "",
        type: "manual",
        icon: "link",
        isEditing: true,
      })
    );
    this.collapsed = false;
    this.args.onChange?.();
  }

  @action
  showTopicChooser() {
    if (this.linkLimitReached) {
      return;
    }
    this.showingTopicChooser = true;
    this.collapsed = false;
  }

  @action
  onAddTopic(topicId, topic) {
    if (!topic || this.linkLimitReached) {
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
  reviewUnindexedTopics() {
    this.#addMenuApi?.close();
    this.args.onReviewUnindexedTopics?.(this.args.section);
  }

  /**
   * Returned rather than fired and forgotten: the list waits on it before
   * announcing the removal and re-placing focus, so cancelling is not spoken as
   * a removal that happened.
   */
  @action
  removeLink(link) {
    return this.dialog.yesNoConfirm({
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

  /** What to call a link: its own title, or the placeholder standing for one. */
  @action
  linkLabel(link) {
    return (
      link.title ||
      i18n(
        "doc_categories.category_settings.index_editor.link_title_placeholder"
      )
    );
  }

  /**
   * The row class, carrying the duplicate mark. On the row element rather than
   * inside it, because that element is the list's and the mark applies to the
   * whole row.
   */
  @action
  linkRowClass(link) {
    return this.args.duplicateHrefs?.has(link.href)
      ? "doc-category-index-editor__link --duplicate"
      : "doc-category-index-editor__link";
  }

  <template>
    {{! The row element belongs to the list: it carries the drag registration,
        the class and the keyed identity, and this fills it. }}
    {{#if @batchMode}}
      <label class="doc-category-index-editor__batch-checkbox">
        <input
          checked={{@isSectionSelected @section}}
          type="checkbox"
          {{on "click" (fn @toggleSectionSelection @section)}}
        />
      </label>
    {{else if @controls.handle}}
      {{! On every viewport, unlike the grip it replaces: it is the menu
          trigger and the keyboard path as well as the drag, so hiding it
          where a drag is impractical would remove the reorder entirely. }}
      <@controls.handle class="doc-category-index-editor__drag-handle" />
    {{/if}}

    <div
      class={{dConcatClass
        "doc-category-index-editor__section"
        (if (@isSectionSelected @section) "--selected")
        (if (or this.titleValidationError this.missingTitleError) "--error")
      }}
      {{! A batch selection of sections lands here rather than on the row: the
            row belongs to the list, which is switched off in batch mode. }}
      {{dDragAndDropTarget
        accepts=SECTION_DRAG_TYPE
        acceptsSelf=false
        canDrop=this.canDropBatchSections
        onDrop=this.onBatchSectionDrop
      }}
      {{! A collapsed section has no rows on screen to aim at, so a link held
            over it opens it. The dwell owns the wait and the cancelling. }}
      {{dDragDwell types=@group.token onDwell=this.expandForDrag}}
    >
      {{#if @section.autoIndex}}
        <DMenu
          title={{i18n
            "doc_categories.category_settings.index_editor.auto_index_badge_title"
          }}
          @identifier="auto-index-badge-menu"
          @triggerClass="doc-category-index-editor__auto-index-badge"
        >
          <:trigger>
            {{icon (if @pendingResync "arrows-rotate" "bolt")}}
            {{if
              @pendingResync
              (i18n
                "doc_categories.category_settings.index_editor.resync_auto_index"
              )
              (if
                @autoIndexIncludeSubcategories
                (i18n
                  "doc_categories.category_settings.index_editor.auto_index_badge_label_with_subcategories"
                )
                (i18n
                  "doc_categories.category_settings.index_editor.auto_index_badge_label"
                )
              )
            }}
            {{icon "angle-down"}}
          </:trigger>
          <:content as |args|>
            <DDropdownMenu as |dropdown|>
              <dropdown.item>
                <label
                  class="doc-category-index-editor__auto-index-subcategories"
                >
                  <input
                    checked={{@autoIndexIncludeSubcategories}}
                    type="checkbox"
                    {{on
                      "change"
                      (fn @onToggleAutoIndexIncludeSubcategories args.close)
                    }}
                  />
                  {{i18n
                    "doc_categories.category_settings.index_editor.include_subcategories"
                  }}
                </label>
              </dropdown.item>
              {{#unless @hideResyncToggle}}
                <dropdown.divider />
                <dropdown.item>
                  <DButton
                    class="btn-transparent"
                    @action={{fn @onToggleResyncAutoIndex args.close}}
                    @icon={{if @pendingResync "xmark" "arrows-rotate"}}
                    @label={{if
                      @pendingResync
                      "doc_categories.category_settings.index_editor.cancel_resync"
                      "doc_categories.category_settings.index_editor.resync_auto_index"
                    }}
                  />
                </dropdown.item>
              {{/unless}}
            </DDropdownMenu>
          </:content>
        </DMenu>
      {{/if}}

      <div class="doc-category-index-editor__section-header">
        <DButton
          class="btn-flat btn-small doc-category-index-editor__collapse-btn"
          @action={{this.toggleCollapsed}}
          @icon={{if this.collapsed "angle-right" "angle-down"}}
        />

        {{#if this.editingTitle}}
          <input
            class="doc-category-index-editor__section-title"
            placeholder={{i18n
              "doc_categories.category_settings.index_editor.section_title_placeholder"
            }}
            type="text"
            value={{this._editSectionTitle}}
            {{dAutoFocus selectText=true}}
            {{on "input" this.updateTitle}}
            {{on "keydown" this.onTitleKeydown}}
          />
          <DButton
            class="btn-flat btn-small doc-category-index-editor__confirm-title-btn"
            @action={{this.confirmTitleEdit}}
            @icon="check"
            @title="doc_categories.category_settings.index_editor.confirm_edit"
          />
          <DButton
            class="btn-flat btn-small doc-category-index-editor__cancel-title-btn"
            @action={{this.cancelTitleEdit}}
            @icon="xmark"
            @title="cancel"
          />
        {{else}}
          {{! eslint-disable ember/template-no-invalid-interactive }}
          <span
            class={{dConcatClass
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
            class="btn-flat btn-small"
            @action={{fn @selectAllInSection @section}}
            @icon="check-double"
            @title="doc_categories.category_settings.index_editor.batch_select_all"
          />
          <DButton
            class="btn-flat btn-small"
            @action={{fn @invertSelectionInSection @section}}
            @icon="right-left"
            @title="doc_categories.category_settings.index_editor.batch_invert"
          />
          <DButton
            class="btn-flat btn-small"
            @action={{fn @clearAllInSection @section}}
            @icon="eraser"
            @title="doc_categories.category_settings.index_editor.batch_clear_selection"
          />
        {{else}}{{#unless this.editingTitle}}
            <DButton
              class="btn-flat btn-small doc-category-index-editor__edit-btn"
              @action={{this.enterTitleEdit}}
              @icon="pencil"
              @title="doc_categories.category_settings.index_editor.edit_section_title"
            />
            {{#if @controls.remove}}
              <@controls.remove
                class="btn-flat btn-small doc-category-index-editor__remove-btn"
              />
            {{/if}}
          {{/unless}}{{/if}}
      </div>

      {{#if (or this.titleValidationError this.missingTitleError)}}
        <div class="doc-category-index-editor__validation-error">
          {{icon "triangle-exclamation"}}
          {{or this.titleValidationError this.missingTitleError}}
        </div>
      {{/if}}

      {{! A batch selection lands in the section as a whole; a single link
            aims at a row, or at the links list itself when there are none.
            Fixed to `before` rather than left to resolve, so the whole body
            reads as the target while the line stays where the links will go. }}
      <div
        aria-hidden={{if this.collapsed "true"}}
        class={{dConcatClass
          "doc-category-index-editor__section-body"
          (if this.collapsed "--collapsed")
          (if this.showsBatchDropSlot "--batch-drop-slot")
        }}
        {{dDragAndDropTarget
          accepts=LINK_DRAG_TYPE
          position="before"
          canDrop=this.canDropBatchLinks
          onDrop=this.onBatchLinkDrop
        }}
      >
        {{! Rendered even while collapsed, so the section stays a registered
              member of the group and keeps standing as a destination in every
              other section's move menu. The body is what hides it. }}
        <div class="doc-category-index-editor__links">
          <DReorderableList
            class="doc-category-index-editor__link-list"
            @controls="manual"
            @disabled={{@batchMode}}
            @group={{@group}}
            @items={{@section.links}}
            @itemTag="div"
            @label={{this.linkLabel}}
            @listId={{@sectionUid}}
            @listLabel={{this.displayTitle}}
            @onRemove={{this.removeLink}}
            @removeIcon="trash-can"
            @rowClass={{this.linkRowClass}}
            @spill={{true}}
            @tag="div"
          >
            <:row as |link controls|>
              <IndexEditorLink
                @batchMode={{@batchMode}}
                @controls={{controls}}
                @duplicateHrefs={{@duplicateHrefs}}
                @favoriteIcons={{@favoriteIcons}}
                @isBatchDraggingItems={{and
                  @isBatchDragging
                  (eq @batchDragType "items")
                }}
                @isSelected={{@isItemSelected link}}
                @link={{link}}
                @onBatchItemDrop={{@onBatchItemDrop}}
                @onChange={{@onChange}}
                @onToggleSelection={{fn @toggleItemSelection link}}
                @searchFilters={{@searchFilters}}
                @section={{@section}}
              />
            </:row>
          </DReorderableList>

          {{#if @section.autoIndex}}
            <div class="doc-category-index-editor__link --ghost">
              {{! The handle renders on every viewport now, so the placeholder
                  standing in its column does too. }}
              <span
                class="doc-category-index-editor__drag-handle-spacer"
              ></span>
              <div class="doc-category-index-editor__link-card --ghost">
                <div class="doc-category-index-editor__link-card-header">
                  <span class="doc-category-index-editor__link-icon">
                    {{icon "far-file"}}
                  </span>
                  <span class="doc-category-index-editor__link-label">
                    {{i18n
                      "doc_categories.category_settings.index_editor.auto_index_placeholder"
                    }}
                  </span>
                </div>
              </div>
            </div>
          {{/if}}
        </div>

        {{#unless this.collapsed}}
          {{#if
            (and
              this.showingTopicChooser
              (not @batchMode)
              (not this.linkLimitReached)
            )
          }}
            <div class="doc-category-index-editor__inline-topic-chooser">
              <div class="doc-category-index-editor__link-card --adding">
                <TopicChooser
                  @content={{this.topicChooserContent}}
                  @onChange={{this.onAddTopic}}
                  @options={{hash
                    additionalFilters=@searchFilters
                    none="doc_categories.category_settings.index_editor.select_topic"
                  }}
                  @value={{null}}
                />
                <DButton
                  class="btn-flat btn-small"
                  @action={{this.cancelTopicChooser}}
                  @icon="xmark"
                />
              </div>
            </div>
          {{/if}}

          {{#unless @batchMode}}
            <div class="doc-category-index-editor__section-actions">
              <DComboButton @hasMenu={{true}}>
                <:default as |combo|>
                  <combo.Button
                    class="btn-default btn-small"
                    @action={{this.showTopicChooser}}
                    @disabled={{this.linkLimitReached}}
                    @icon="plus"
                    @label="doc_categories.category_settings.index_editor.add_topic"
                  />
                  <combo.Menu
                    class="btn-default btn-small"
                    @identifier="section-add-menu"
                    @onRegisterApi={{this.registerAddMenuApi}}
                  >
                    <DDropdownMenu as |dropdown|>
                      <dropdown.item>
                        <DButton
                          class="btn-transparent"
                          @action={{this.addManualLink}}
                          @disabled={{this.linkLimitReached}}
                          @icon="link"
                          @label="doc_categories.category_settings.index_editor.add_link"
                        />
                      </dropdown.item>
                      {{! Auto-index already gathers what the index leaves out
                          into its own section. }}
                      {{#unless @section.autoIndex}}
                        <dropdown.divider />
                        <dropdown.item>
                          <DButton
                            class="btn-transparent doc-category-index-editor__review-section-topics"
                            @action={{this.reviewUnindexedTopics}}
                            @icon="list-check"
                            @label="doc_categories.category_settings.index_editor.add_missing_topics"
                          />
                        </dropdown.item>
                      {{/unless}}
                    </DDropdownMenu>
                  </combo.Menu>
                </:default>
              </DComboButton>
              {{#if this.linkLimitReached}}
                <span class="doc-category-index-editor__capacity-message">
                  {{this.linkLimitMessage}}
                </span>
              {{/if}}
            </div>
          {{/unless}}
        {{/unless}}
      </div>
    </div>
  </template>
}
