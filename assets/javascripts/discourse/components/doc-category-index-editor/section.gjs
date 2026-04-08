import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trackedObject } from "@ember/reactive/collections";
import { cancel } from "@ember/runloop";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DComboButton from "discourse/components/d-combo-button";
import DropdownMenu from "discourse/components/dropdown-menu";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import { popupAjaxError } from "discourse/lib/ajax-error";
import discourseLater from "discourse/lib/later";
import autoFocus from "discourse/modifiers/auto-focus";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { and, eq, not, or } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import { IndexEditorLink } from "./link";

export class IndexEditorSection extends Component {
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
    // New sections with empty title auto-enter title edit mode,
    // but the first section is allowed to have an empty title
    if (
      !this.args.section.title &&
      !this.args.isFirstSection?.(this.args.section)
    ) {
      this._isNew = true;
      this._editSectionTitle = "";
      this.editingTitle = true;
    }
  }

  willDestroy() {
    super.willDestroy();
    if (this._autoExpandTimer) {
      cancel(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
    // Ensure editingCount is decremented if destroyed while editing title
    if (this.editingTitle) {
      this.args.onEditStateChange?.(false);
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
    this.args.onEditStateChange?.(true);
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
    const domRect = event.currentTarget.getBoundingClientRect();
    return event.clientY - domRect.top < domRect.height / 2;
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
    this.dragCssClass = "is-dragging";
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
    if (this.dragCssClass === "is-dragging") {
      return;
    }
    const isBatchSectionDrag =
      this.args.isBatchDragging && this.args.batchDragType === "sections";
    if (this.args.isDraggingSection || isBatchSectionDrag) {
      this.dragCssClass = this.isAboveElement(event)
        ? "is-drag-above"
        : "is-drag-below";
    }
  }

  @action
  sectionDragEnter() {
    this.dragCount++;
    if (this.collapsed) {
      if (this._autoExpandTimer) {
        cancel(this._autoExpandTimer);
      }
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
      cancel(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
    if (this.dragCount === 0) {
      this.emptyDropTarget = false;
      if (
        this.dragCssClass === "is-drag-above" ||
        this.dragCssClass === "is-drag-below"
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
      cancel(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }

    const hasIndicator =
      this.dragCssClass === "is-drag-above" ||
      this.dragCssClass === "is-drag-below" ||
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
      cancel(this._autoExpandTimer);
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
          role="button"
          aria-label={{i18n
            "doc_categories.category_settings.index_editor.drag_section"
          }}
          {{on "dragstart" this.sectionDragHasStarted}}
        >
          {{icon "grip-lines"}}
        </span>
      {{/if}}

      <div
        class={{concatClass
          "doc-category-index-editor__section"
          (if (@isSectionSelected @section) "--selected")
          (if (or this.titleValidationError this.missingTitleError) "--error")
        }}
      >
        {{#if @section.autoIndex}}
          <span
            class="doc-category-index-editor__auto-index-badge"
            title={{i18n
              "doc_categories.category_settings.index_editor.auto_index_badge_title"
            }}
          >
            {{icon "bolt"}}
            {{i18n
              "doc_categories.category_settings.index_editor.auto_index_badge_label"
            }}
          </span>
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
              <DButton
                @icon="trash-can"
                @action={{fn @onRemove @section}}
                @title="doc_categories.category_settings.index_editor.remove_section"
                class="btn-flat btn-small doc-category-index-editor__remove-btn"
              />
            {{/unless}}{{/if}}
        </div>

        {{#if (or this.titleValidationError this.missingTitleError)}}
          <div class="doc-category-index-editor__validation-error">
            {{icon "triangle-exclamation"}}
            {{or this.titleValidationError this.missingTitleError}}
          </div>
        {{/if}}

        <div
          class={{concatClass
            "doc-category-index-editor__section-body"
            (if this.collapsed "--collapsed")
            (if this.emptyDropTarget "--drop-target")
          }}
          aria-hidden={{if this.collapsed "true"}}
        >
          {{#unless this.collapsed}}
            <div class="doc-category-index-editor__links">
              {{#each @section.links as |link|}}
                <IndexEditorLink
                  @link={{link}}
                  @section={{@section}}
                  @searchFilters={{@searchFilters}}
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

              {{#if @section.autoIndex}}
                <div class="doc-category-index-editor__link --ghost">
                  {{#if this.site.desktopView}}
                    <span
                      class="doc-category-index-editor__drag-handle-spacer"
                    ></span>
                  {{/if}}
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
