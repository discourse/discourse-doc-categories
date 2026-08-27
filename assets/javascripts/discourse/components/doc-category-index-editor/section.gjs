import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trackedObject } from "@ember/reactive/collections";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DComboButton from "discourse/components/d-combo-button";
import DropdownMenu from "discourse/components/dropdown-menu";
import DMenu from "discourse/float-kit/components/d-menu";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { popupAjaxError } from "discourse/lib/ajax-error";
import autoFocus from "discourse/modifiers/auto-focus";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { and, eq, not, or } from "discourse/truth-helpers";
import DReorderableList from "discourse/ui-kit/d-reorderable-list";
import dDragAndDropTarget from "discourse/ui-kit/modifiers/d-drag-and-drop-target";
import dDragDwell from "discourse/ui-kit/modifiers/d-drag-dwell";
import { i18n } from "discourse-i18n";
import { IndexEditorLink, LINK_DRAG_TYPE } from "./link";

/** What a dragged batch selection of sections publishes. */
export const SECTION_DRAG_TYPE = "doc-index-section";

export class IndexEditorSection extends Component {
  @service dialog;

  @tracked titleValidationError = null;

  @tracked includeSubcategories = false;

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

  get linkCount() {
    return this.args.section.links.length;
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
    this.showingTopicChooser = true;
    this.collapsed = false;
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
  toggleIncludeSubcategories() {
    this.includeSubcategories = !this.includeSubcategories;
  }

  @action
  async addMissingTopicsToSection() {
    this.#addMenuApi?.close();
    const includeSubcategories = this.includeSubcategories;
    try {
      const result = await this.args.fetchTopics(includeSubcategories);
      if (this.isDestroying || this.isDestroyed) {
        return;
      }
      if (result.topics.length === 0) {
        this.dialog.alert(
          i18n("doc_categories.category_settings.index_editor.no_topics_found")
        );
        return;
      }
      const existingHrefs = new Set(
        this.args.section.links.map((link) => link.href).filter(Boolean)
      );
      const missing = result.topics.filter(
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
            topic_id: topic.id,
            topicTitle: topic.title || topic.fancy_title,
            autoTitle: true,
          })
        );
      }
      this.collapsed = false;
      this.args.onChange?.();
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
          type="checkbox"
          checked={{@isSectionSelected @section}}
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
      class={{concatClass
        "doc-category-index-editor__section"
        (if (@isSectionSelected @section) "--selected")
        (if (or this.titleValidationError this.missingTitleError) "--error")
      }}
    >
      {{#if @section.autoIndex}}
        <DMenu
          @identifier="auto-index-badge-menu"
          @triggerClass="doc-category-index-editor__auto-index-badge"
          title={{i18n
            "doc_categories.category_settings.index_editor.auto_index_badge_title"
          }}
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
            <DropdownMenu as |dropdown|>
              <dropdown.item>
                <label
                  class="doc-category-index-editor__auto-index-subcategories"
                >
                  <input
                    type="checkbox"
                    checked={{@autoIndexIncludeSubcategories}}
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
                    @icon={{if @pendingResync "xmark" "arrows-rotate"}}
                    @label={{if
                      @pendingResync
                      "doc_categories.category_settings.index_editor.cancel_resync"
                      "doc_categories.category_settings.index_editor.resync_auto_index"
                    }}
                    @action={{fn @onToggleResyncAutoIndex args.close}}
                    class="btn-transparent"
                  />
                </dropdown.item>
              {{/unless}}
            </DropdownMenu>
          </:content>
        </DMenu>
      {{/if}}

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
            {{autoFocus selectText=true}}
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
            @title="doc_categories.category_settings.index_editor.batch_clear_selection"
            class="btn-flat btn-small"
          />
        {{else}}{{#unless this.editingTitle}}
            <DButton
              @icon="pencil"
              @action={{this.enterTitleEdit}}
              @title="doc_categories.category_settings.index_editor.edit_section_title"
              class="btn-flat btn-small doc-category-index-editor__edit-btn"
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
        {{dDragAndDropTarget
          accepts=LINK_DRAG_TYPE
          position="before"
          canDrop=this.canDropBatchLinks
          onDrop=this.onBatchLinkDrop
        }}
        class={{concatClass
          "doc-category-index-editor__section-body"
          (if this.collapsed "--collapsed")
        }}
        aria-hidden={{if this.collapsed "true"}}
      >
        {{! Rendered even while collapsed, so the section stays a registered
              member of the group and keeps standing as a destination in every
              other section's move menu. The body is what hides it. }}
        <div class="doc-category-index-editor__links">
          <DReorderableList
            @group={{@group}}
            @listId={{@sectionUid}}
            @listLabel={{this.displayTitle}}
            @spill={{true}}
            @items={{@section.links}}
            @label={{this.linkLabel}}
            @onRemove={{this.removeLink}}
            @removeIcon="trash-can"
            @disabled={{@batchMode}}
            @controls="manual"
            @tag="div"
            @itemTag="div"
            @rowClass={{this.linkRowClass}}
            class="doc-category-index-editor__link-list"
          >
            <:row as |link controls|>
              <IndexEditorLink
                @link={{link}}
                @section={{@section}}
                @controls={{controls}}
                @searchFilters={{@searchFilters}}
                @duplicateHrefs={{@duplicateHrefs}}
                @favoriteIcons={{@favoriteIcons}}
                @batchMode={{@batchMode}}
                @isBatchDraggingItems={{and
                  @isBatchDragging
                  (eq @batchDragType "items")
                }}
                @isSelected={{@isItemSelected link}}
                @onToggleSelection={{fn @toggleItemSelection link}}
                @onBatchItemDrop={{@onBatchItemDrop}}
                @onChange={{@onChange}}
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
          {{#if (and this.showingTopicChooser (not @batchMode))}}
            <div class="doc-category-index-editor__inline-topic-chooser">
              <div class="doc-category-index-editor__link-card --adding">
                <TopicChooser
                  @value={{null}}
                  @content={{this.topicChooserContent}}
                  @onChange={{this.onAddTopic}}
                  @options={{hash
                    additionalFilters=@searchFilters
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
              <DComboButton @hasMenu={{true}}>
                <:default as |combo|>
                  <combo.Button
                    @action={{this.showTopicChooser}}
                    @icon="plus"
                    @label="doc_categories.category_settings.index_editor.add_topic"
                    class="btn-default btn-small"
                  />
                  <combo.Menu
                    @identifier="section-add-menu"
                    @onRegisterApi={{this.registerAddMenuApi}}
                    class="btn-default btn-small"
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
  </template>
}
