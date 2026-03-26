import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { trackedArray, trackedObject } from "@ember/reactive/collections";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import DButton from "discourse/components/d-button";
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
import { not, or } from "discourse/truth-helpers";
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
  dragCount = 0;

  constructor() {
    super(...arguments);
    /* New empty links auto-enter edit mode */
    if (!this.args.link.title && !this.args.link.href) {
      this.editing = true;
    }
  }

  get isTopicLink() {
    return this.args.link.type === "topic";
  }

  @action
  switchToManualLink() {
    this.args.link.type = "manual";
    this.args.link.href = "";
    this.swapping = false;
    this.swapTopicContent = [];
    this.args.onChange?.();
  }

  @action
  switchToTopicLink() {
    this.args.link.type = "topic";
    this.args.link.href = "";
    this.swapping = true;
    this.args.onChange?.();
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
    return !!this.args.link.href;
  }

  @action
  enterEdit() {
    this.editing = true;
  }

  @action
  confirmEdit() {
    if (!this.canConfirm) {
      return;
    }
    this.editing = false;
    this.swapping = false;
    this.swapTopicContent = [];
  }

  @action
  cancelEdit() {
    this.editing = false;
    this.swapping = false;
    this.swapTopicContent = [];
  }

  @action
  onCardFocusOut(event) {
    const card = event.currentTarget;
    requestAnimationFrame(() => {
      /* Don't close if focus moved within the card or into a floating menu (icon picker, select-kit) */
      if (
        card.contains(document.activeElement) ||
        document.querySelector(
          ".fk-d-menu__content, .select-kit-body, .d-modal"
        )
      ) {
        return;
      }
      /* Don't auto-close if URL is still empty */
      if (!this.canConfirm) {
        return;
      }
      this.editing = false;
      this.swapping = false;
      this.swapTopicContent = [];
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
    if (this.dragCssClass !== "dragging") {
      const isAbove = this.isAboveElement(event);
      this._isAbove = isAbove;
      this.dragCssClass = isAbove ? "drag-above" : "drag-below";
    }
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
    this.args.onDrop(this.args.link, this.args.section, this._isAbove);
    this.dragCssClass = null;
  }

  @action
  dragEnd() {
    this.dragCount = 0;
    this.dragCssClass = null;
  }

  @action
  updateTitle(event) {
    this.args.link.title = event.target.value;
    this.args.onChange?.();
  }

  @action
  updateHref(event) {
    this.args.link.href = event.target.value;
    this.args.onChange?.();
  }

  @action
  updateIcon(value) {
    this.args.link.icon = value;
    this.args.onChange?.();
  }

  @action
  startSwap() {
    this.swapping = true;
  }

  @action
  onSwapTopic(topicId, topic) {
    if (topic) {
      this.args.link.title = topic.title || topic.fancy_title;
      this.args.link.href = `/t/${topic.slug}/${topic.id}`;
    }
    this.swapping = false;
    this.swapTopicContent = [];
    this.args.onChange?.();
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
      {{#if this.site.desktopView}}
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
          class="doc-category-index-editor__link-card --editing"
          {{on "focusout" this.onCardFocusOut}}
        >
          <div class="doc-category-index-editor__link-edit-row">
            <DIconGridPicker
              @value={{@link.icon}}
              @onChange={{this.updateIcon}}
              @favorites={{@favoriteIcons}}
              @showSelectedName={{true}}
            />
            <input
              type="text"
              value={{@link.title}}
              placeholder={{i18n
                "doc_categories.category_settings.index_editor.link_title_placeholder"
              }}
              class="doc-category-index-editor__link-title"
              {{autoFocus}}
              {{on "input" this.updateTitle}}
            />
          </div>

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
                  {{@link.href}}
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
                value={{@link.href}}
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
          class="doc-category-index-editor__link-card"
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
  @tracked collapsed = false;
  @tracked editingTitle = false;
  @tracked showingTopicChooser = false;
  @tracked topicChooserContent = [];
  dragCount = 0;
  _autoExpandTimer = null;

  constructor() {
    super(...arguments);
    /* New sections with empty title auto-enter title edit mode */
    if (!this.args.section.title) {
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
    this.editingTitle = true;
  }

  @action
  confirmTitleEdit() {
    this.editingTitle = false;
  }

  @action
  onTitleKeydown(event) {
    if (event.key === "Enter" || event.key === "Escape") {
      event.preventDefault();
      this.confirmTitleEdit();
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

  @action
  sectionDragOver(event) {
    event.preventDefault();
    if (this.dragCssClass === "dragging") {
      return;
    }
    /* Only show section drop indicators when a section is being dragged */
    if (!this.args.isDraggingSection) {
      return;
    }
    this.dragCssClass = this.isAboveElement(event)
      ? "drag-above"
      : "drag-below";
  }

  @action
  sectionDragEnter() {
    this.dragCount++;
    if (this.collapsed) {
      this._autoExpandTimer = discourseLater(() => {
        this.collapsed = false;
      }, 500);
    }
  }

  @action
  sectionDragLeave() {
    this.dragCount--;
    if (this._autoExpandTimer && this.dragCount === 0) {
      clearTimeout(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
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
  sectionDropItem(event) {
    event.stopPropagation();
    this.dragCount = 0;
    if (this._autoExpandTimer) {
      clearTimeout(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
    this.args.onSectionDrop(this.args.section, this.isAboveElement(event));
    this.dragCssClass = null;
  }

  @action
  sectionDragEnd() {
    this.dragCount = 0;
    this.dragCssClass = null;
    this.args.onSectionDragEnd?.();
    if (this._autoExpandTimer) {
      clearTimeout(this._autoExpandTimer);
      this._autoExpandTimer = null;
    }
  }

  @action
  updateTitle(event) {
    this.args.section.title = event.target.value;
    this.args.onChange?.();
  }

  @action
  addManualLinkAndClose(closeMenu) {
    this.args.section.links.push(
      trackedObject({ title: "", href: "", type: "manual", icon: "link" })
    );
    this.collapsed = false;
    closeMenu?.();
    this.args.onChange?.();
  }

  @action
  showTopicChooserAndClose(closeMenu) {
    this.showingTopicChooser = true;
    this.collapsed = false;
    closeMenu?.();
  }

  @action
  onAddTopic(topicId, topic) {
    if (!topic) {
      return;
    }
    this.args.section.links.push(
      trackedObject({
        title: topic.title || topic.fancy_title,
        href: `/t/${topic.slug}/${topic.id}`,
        type: "topic",
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
      {{#if this.site.desktopView}}
        <span
          class="doc-category-index-editor__drag-handle"
          draggable="true"
          {{on "dragstart" this.sectionDragHasStarted}}
        >
          {{icon "grip-lines"}}
        </span>
      {{/if}}

      <div class="doc-category-index-editor__section">
        <div class="doc-category-index-editor__section-header">
          <DButton
            @icon={{if this.collapsed "angle-right" "angle-down"}}
            @action={{this.toggleCollapsed}}
            class="btn-flat btn-small doc-category-index-editor__collapse-btn"
          />

          {{#if this.editingTitle}}
            <input
              type="text"
              value={{@section.title}}
              placeholder={{i18n
                "doc_categories.category_settings.index_editor.section_title_placeholder"
              }}
              class="doc-category-index-editor__section-title"
              {{autoFocus}}
              {{on "input" this.updateTitle}}
              {{on "keydown" this.onTitleKeydown}}
              {{on "focusout" this.confirmTitleEdit}}
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
        </div>

        <div
          class={{concatClass
            "doc-category-index-editor__section-body"
            (if this.collapsed "--collapsed")
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
                  @onRemove={{this.removeLink}}
                  @onDragStart={{@onLinkDragStart}}
                  @onDrop={{@onLinkDrop}}
                  @onChange={{@onChange}}
                />
              {{/each}}
            </div>

            {{#if this.showingTopicChooser}}
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

            <div class="doc-category-index-editor__section-actions">
              <DMenu
                @identifier="add-item-menu"
                class="doc-category-index-editor__add-menu"
              >
                <:trigger>
                  {{icon "plus"}}
                  <span>{{i18n
                      "doc_categories.category_settings.index_editor.add"
                    }}</span>
                </:trigger>
                <:content as |menuArgs|>
                  <DropdownMenu as |dropdown|>
                    <dropdown.item>
                      <DButton
                        @icon="file"
                        @label="doc_categories.category_settings.index_editor.add_topic"
                        @action={{fn
                          this.showTopicChooserAndClose
                          menuArgs.close
                        }}
                        class="btn-transparent"
                      />
                    </dropdown.item>
                    <dropdown.item>
                      <DButton
                        @icon="link"
                        @label="doc_categories.category_settings.index_editor.add_link"
                        @action={{fn this.addManualLinkAndClose menuArgs.close}}
                        class="btn-transparent"
                      />
                    </dropdown.item>
                  </DropdownMenu>
                </:content>
              </DMenu>
            </div>
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
  draggedSection = null;
  _draggedLink = null;
  _draggedLinkSourceSection = null;

  _syncSectionsToCategory = () => {
    const serialized = this._serializeSections();
    this.args.category?.set(
      "doc_index_sections",
      serialized.length > 0 ? JSON.stringify(serialized) : null
    );
  };

  constructor() {
    super(...arguments);
    this.args.registerValidator?.(this._syncSectionsToCategory);
    this.args.registerAfterReset?.(() => {
      this.sections = trackedArray(this._initSectionsFromModel());
    });
  }

  willDestroy() {
    super.willDestroy();
    this._saveToTransientData();
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
              type: "topic",
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
        icon: link.icon,
      })),
    }));
  }

  @bind
  _saveToTransientData() {
    this.args.form?.set("_docIndexSections", this._serializeSections());
  }

  get isEmpty() {
    return this.sections.length === 0;
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
  async _fetchCategoryTopics() {
    const response = await ajax(
      `/doc-categories/indexes/${this.args.categoryId}/topics`,
      { data: { include_subcategories: this.includeSubcategories } }
    );

    return response.topics || [];
  }

  _topicToLink(topic) {
    return trackedObject({
      title: topic.title || topic.fancy_title,
      href: `/t/${topic.slug}/${topic.id}`,
      type: "topic",
      icon: "far-file",
    });
  }

  get allExistingHrefs() {
    const hrefs = new Set();
    for (const section of this.sections) {
      for (const link of section.links) {
        if (link.href) {
          hrefs.add(link.href);
        }
      }
    }
    return hrefs;
  }

  @action
  toggleIncludeSubcategories() {
    this.includeSubcategories = !this.includeSubcategories;
  }

  @action
  indexAllTopicsAndClose(closeMenu) {
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

  @action
  async addMissingTopicsAndClose(closeMenu) {
    closeMenu?.();
    return this.addMissingTopics();
  }

  @action
  async addMissingTopics() {
    try {
      const topics = await this._fetchCategoryTopics();
      if (topics.length === 0) {
        return;
      }
      const existingHrefs = this.allExistingHrefs;
      const missing = topics.filter(
        (t) => !existingHrefs.has(`/t/${t.slug}/${t.id}`)
      );
      if (missing.length === 0) {
        return;
      }
      this.sections.push(
        trackedObject({
          title: i18n(
            "doc_categories.category_settings.index_editor.missing_topics_section"
          ),
          links: trackedArray(missing.map((t) => this._topicToLink(t))),
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
    this.saveState = "saving";
    const payload = {
      sections: this.sections.map((section) => ({
        title: section.title,
        links: section.links.map((link) => ({
          title: link.title,
          href: link.href,
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

  get applyDisabled() {
    return this.saveState === "saving" || !this.hasPendingChanges;
  }

  <template>
    <div class="doc-category-index-editor">
      <div class="doc-category-index-editor__toolbar">
        <DMenu
          @identifier="auto-index-menu"
          class="doc-category-index-editor__auto-index-menu"
        >
          <:trigger>
            {{icon "arrows-rotate"}}
            <span>{{i18n
                "doc_categories.category_settings.index_editor.auto_index"
              }}</span>
          </:trigger>
          <:content as |menuArgs|>
            <DropdownMenu as |dropdown|>
              <dropdown.item>
                <label class="doc-category-index-editor__subcategory-toggle">
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
                  @icon="arrows-rotate"
                  @label="doc_categories.category_settings.index_editor.index_all_topics"
                  @action={{fn this.indexAllTopicsAndClose menuArgs.close}}
                  class="btn-transparent"
                />
              </dropdown.item>
              <dropdown.item>
                <DButton
                  @icon="plus"
                  @label="doc_categories.category_settings.index_editor.add_missing_topics"
                  @action={{fn this.addMissingTopicsAndClose menuArgs.close}}
                  class="btn-transparent"
                />
              </dropdown.item>
            </DropdownMenu>
          </:content>
        </DMenu>
      </div>

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
            @onRemove={{this.removeSection}}
            @onSectionDragStart={{this.setDraggedSection}}
            @onSectionDragEnd={{this.clearDraggedSection}}
            @onSectionDrop={{this.reorderSection}}
            @onLinkDragStart={{this.onLinkDragStart}}
            @onLinkDrop={{this.onLinkDrop}}
            @onChange={{this._saveToTransientData}}
          />
        {{/each}}
      </div>

      <div class="doc-category-index-editor__footer">
        <DButton
          @icon="plus"
          @label="doc_categories.category_settings.index_editor.add_section"
          @action={{this.addSection}}
          class="btn-default btn-small"
        />

        <DButton
          @icon="check"
          @label={{this.applyLabel}}
          @action={{this.apply}}
          @disabled={{this.applyDisabled}}
          class="btn-default doc-category-index-editor__apply-btn"
        />
      </div>
    </div>
  </template>
}
