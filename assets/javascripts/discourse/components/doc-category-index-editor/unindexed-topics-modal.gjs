import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { trackedMap } from "@ember/reactive/collections";
import { cancel } from "@ember/runloop";
import Form from "discourse/components/form";
import { extractError } from "discourse/lib/ajax-error";
import discourseDebounce from "discourse/lib/debounce";
import getURL from "discourse/lib/get-url";
import Category from "discourse/models/category";
import DButton from "discourse/ui-kit/d-button";
import DModal from "discourse/ui-kit/d-modal";
import DModalCancel from "discourse/ui-kit/d-modal-cancel";
import dCategoryBadge from "discourse/ui-kit/helpers/d-category-badge";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import dLoadingSpinner from "discourse/ui-kit/helpers/d-loading-spinner";
import { i18n } from "discourse-i18n";
import { MAX_LINKS_PER_SECTION } from "../../lib/constants.js";
import { fetchUnindexedTopics } from "../../lib/doc-index-unindexed-topics.js";

const MAX_SEARCH_LENGTH = 200;
const SEARCH_DELAY = 300;

/** Nothing reaches the draft until Add, and then only through `@model.addTopics`. */
export default class UnindexedTopicsModal extends Component {
  @tracked flash = null;
  @tracked isLoading = false;
  @tracked isQueryPending = false;
  @tracked retryRequest = null;
  @tracked topics = [];
  @tracked totalCount = 0;
  @tracked hasMore = false;
  @tracked destination;
  formData = {
    include_subcategories: !!this.args.model.includeSubcategories,
    search: "",
    section_id: this.args.model.initialDestination,
  };

  /** By id, so a choice survives loading more and searching. */
  selected = trackedMap();
  #formApi = null;
  #includeSubcategories = !!this.args.model.includeSubcategories;
  #page = 0;
  #searchTimer = null;
  #sequence = 0;
  @tracked _search = "";

  constructor() {
    super(...arguments);
    this.destination = this.args.model.initialDestination;
    this.#load();
  }

  willDestroy() {
    super.willDestroy(...arguments);
    cancel(this.#searchTimer);
  }

  get canLoadMore() {
    return !this.retryRequest && this.hasMore;
  }

  get isBusy() {
    return this.isLoading || this.isQueryPending;
  }

  get hasListActions() {
    return this.topics.length > 0 || this.selected.size > 0;
  }

  get destinationOption() {
    return this.args.model.destinations.find(
      (option) => option.value === this.destination
    );
  }

  get availableSlots() {
    return Math.max(
      0,
      MAX_LINKS_PER_SECTION - (this.destinationOption?.linkCount ?? 0)
    );
  }

  get capacityMessage() {
    if (this.selected.size <= this.availableSlots) {
      return null;
    }
    const section = this.destinationOption?.label;
    if (this.availableSlots === 0) {
      return i18n(
        "doc_categories.category_settings.index_editor.unindexed_topics.section_full",
        { section }
      );
    }
    return i18n(
      "doc_categories.category_settings.index_editor.unindexed_topics.section_room",
      { section, count: this.availableSlots }
    );
  }

  get addDisabled() {
    return (
      this.selected.size === 0 ||
      !this.destinationOption ||
      !!this.capacityMessage
    );
  }

  get addLabel() {
    if (this.selected.size === 0) {
      return i18n(
        "doc_categories.category_settings.index_editor.unindexed_topics.add_none"
      );
    }
    return i18n(
      "doc_categories.category_settings.index_editor.unindexed_topics.add",
      { count: this.selected.size }
    );
  }

  get emptyMessage() {
    return this._search
      ? i18n(
          "doc_categories.category_settings.index_editor.unindexed_topics.none_match"
        )
      : i18n(
          "doc_categories.category_settings.index_editor.unindexed_topics.none_found"
        );
  }

  @action
  registerApi(api) {
    this.#formApi = api;
  }

  @action
  updateDestination(value, { set, name }) {
    set(name, value);
    this.destination = value;
  }

  @action
  updateSearch(value, { set, name }) {
    const search = String(value ?? "").slice(0, MAX_SEARCH_LENGTH);
    set(name, search);

    const query = search.trim();
    if (query === this._search) {
      return;
    }

    this._search = query;
    this.#invalidateQuery();
    this.isQueryPending = true;
    this.#searchTimer = discourseDebounce(this, this.#load, SEARCH_DELAY);
  }

  @action
  updateScope(value, { set, name }) {
    set(name, value);
    this.#includeSubcategories = !!value;
    this.clearSelection();
    this.#invalidateQuery();
    this.#load();
  }

  @action
  toggleTopic(topic, checked, { set, name }) {
    set(name, checked);
    if (checked) {
      this.selected.set(topic.id, topic);
    } else {
      this.selected.delete(topic.id);
    }
  }

  @action
  selectShown() {
    const values = {};
    for (const topic of this.topics) {
      values[this.#fieldName(topic.id)] = true;
      this.selected.set(topic.id, topic);
    }
    this.#formApi?.setProperties(values);
  }

  @action
  clearSelection() {
    const values = {};
    for (const id of this.selected.keys()) {
      values[this.#fieldName(id)] = false;
    }
    this.selected.clear();
    this.#formApi?.setProperties(values);
  }

  @action
  loadMore() {
    if (this.isBusy || this.retryRequest) {
      return;
    }
    this.#load({ append: true });
  }

  @action
  retry() {
    if (!this.retryRequest || this.isBusy) {
      return;
    }
    this.#load(this.retryRequest);
  }

  @action
  add() {
    if (this.addDisabled) {
      return;
    }

    const result = this.args.model.addTopics({
      topics: [...this.selected.values()],
      destination: this.destination,
    });
    if (result?.error) {
      this.flash = result.error;
      return;
    }
    this.args.closeModal();
  }

  @action
  subcategoryOf(topic) {
    if (topic.category_id === this.args.model.categoryId) {
      return null;
    }
    return Category.findById(topic.category_id);
  }

  @action
  topicUrl(topic) {
    return getURL(`/t/${topic.slug}/${topic.id}`);
  }

  @action
  fieldName(topic) {
    return this.#fieldName(topic.id);
  }

  #fieldName(id) {
    return `topic_${id}`;
  }

  /** Drops everything the previous query produced before its replacement runs. */
  #invalidateQuery() {
    this.#sequence++;
    cancel(this.#searchTimer);
    this.#searchTimer = null;
    this.#page = 0;
    this.isLoading = false;
    this.isQueryPending = false;
    this.retryRequest = null;
    this.topics = [];
    this.totalCount = 0;
    this.hasMore = false;
    this.flash = null;
  }

  #isCurrent(sequence) {
    return !this.isDestroying && sequence === this.#sequence;
  }

  async #load({ append = false } = {}) {
    const sequence = ++this.#sequence;
    const page = append ? this.#page + 1 : 0;

    cancel(this.#searchTimer);
    this.#searchTimer = null;
    this.isQueryPending = false;
    this.retryRequest = null;
    this.isLoading = true;

    try {
      const result = await fetchUnindexedTopics(this.args.model.categoryId, {
        references: this.args.model.getReferences(),
        includeSubcategories: this.#includeSubcategories,
        search: this._search,
        page,
      });
      if (!this.#isCurrent(sequence)) {
        return;
      }

      this.#page = page;
      if (append) {
        const shown = new Set(this.topics.map((topic) => topic.id));
        this.topics = [
          ...this.topics,
          ...result.topics.filter((topic) => !shown.has(topic.id)),
        ];
      } else {
        this.topics = result.topics;
      }
      this.totalCount = result.totalCount;
      this.hasMore = result.hasMore;
      this.flash = null;
    } catch (error) {
      if (!this.#isCurrent(sequence)) {
        return;
      }
      this.flash = extractError(error);
      this.retryRequest = { append };
    } finally {
      if (this.#isCurrent(sequence)) {
        this.isLoading = false;
      }
    }
  }

  <template>
    <DModal
      class="doc-category-unindexed-topics"
      @closeModal={{@closeModal}}
      @flash={{this.flash}}
      @flashType="error"
      @inline={{@inline}}
      @subtitle={{i18n
        "doc_categories.category_settings.index_editor.unindexed_topics.modal_subtitle"
      }}
      @title={{i18n
        "doc_categories.category_settings.index_editor.unindexed_topics.modal_title"
      }}
    >
      <:body>
        <Form
          @data={{this.formData}}
          @onRegisterApi={{this.registerApi}}
          as |form|
        >
          <form.Field
            @format="full"
            @name="section_id"
            @onSet={{this.updateDestination}}
            @title={{i18n
              "doc_categories.category_settings.index_editor.unindexed_topics.section_field"
            }}
            @type="select"
            @validation="required"
            as |field|
          >
            <field.Control @includeNone={{false}} as |select|>
              {{#each @model.destinations as |option|}}
                <select.Option @value={{option.value}}>
                  {{option.label}}
                </select.Option>
              {{/each}}
            </field.Control>
          </form.Field>

          <form.Field
            @format="full"
            @name="search"
            @onSet={{this.updateSearch}}
            @title={{i18n
              "doc_categories.category_settings.index_editor.unindexed_topics.search_field"
            }}
            @type="input"
            as |field|
          >
            <field.Control
              maxlength={{MAX_SEARCH_LENGTH}}
              placeholder={{i18n
                "doc_categories.category_settings.index_editor.unindexed_topics.search_placeholder"
              }}
            />
          </form.Field>

          {{#if @model.canIncludeSubcategories}}
            <form.Field
              @name="include_subcategories"
              @onSet={{this.updateScope}}
              @title={{i18n
                "doc_categories.category_settings.index_editor.include_subcategories"
              }}
              @type="checkbox"
              as |field|
            >
              <field.Control />
            </form.Field>
          {{/if}}

          <form.CheckboxGroup
            @title={{i18n
              "doc_categories.category_settings.index_editor.unindexed_topics.topics_title"
            }}
            as |group|
          >
            {{#each this.topics key="id" as |topic|}}
              <group.Field
                class="doc-category-unindexed-topics__topic"
                data-topic-id={{topic.id}}
                @format="full"
                @name={{this.fieldName topic}}
                @onSet={{fn this.toggleTopic topic}}
                @title={{topic.title}}
                @type="checkbox"
                as |field|
              >
                <field.Control>
                  {{#let (this.subcategoryOf topic) as |subcategory|}}
                    {{#if subcategory}}
                      {{dCategoryBadge subcategory}}
                    {{/if}}
                  {{/let}}
                </field.Control>
                <a
                  aria-label={{i18n
                    "doc_categories.category_settings.index_editor.unindexed_topics.open_topic"
                    title=topic.title
                  }}
                  class="doc-category-unindexed-topics__topic-link"
                  href={{this.topicUrl topic}}
                  rel="noopener noreferrer"
                  target="_blank"
                  title={{i18n
                    "doc_categories.category_settings.index_editor.unindexed_topics.open_topic"
                    title=topic.title
                  }}
                >
                  {{dIcon "up-right-from-square"}}
                </a>
              </group.Field>
            {{else}}
              {{#if this.isBusy}}
                {{dLoadingSpinner size="small"}}
              {{else}}
                {{#unless this.retryRequest}}
                  <p class="doc-category-unindexed-topics__empty">
                    {{this.emptyMessage}}
                  </p>
                {{/unless}}
              {{/if}}
            {{/each}}
          </form.CheckboxGroup>

          {{#if this.hasListActions}}
            <div class="doc-category-unindexed-topics__list-actions">
              <span class="doc-category-unindexed-topics__counts">
                {{#if this.topics.length}}
                  {{i18n
                    "doc_categories.category_settings.index_editor.unindexed_topics.shown"
                    shown=this.topics.length
                    total=this.totalCount
                  }}
                {{/if}}
                {{#if this.selected.size}}
                  {{#if this.topics.length}}
                    ·
                  {{/if}}
                  {{i18n
                    "doc_categories.category_settings.index_editor.unindexed_topics.selected"
                    count=this.selected.size
                  }}
                {{/if}}
              </span>
              {{#if this.topics.length}}
                <DButton
                  class="btn-flat btn-small doc-category-unindexed-topics__select-shown"
                  @action={{this.selectShown}}
                  @label="doc_categories.category_settings.index_editor.unindexed_topics.select_shown"
                />
              {{/if}}
              {{#if this.selected.size}}
                <DButton
                  class="btn-flat btn-small doc-category-unindexed-topics__clear-selection"
                  @action={{this.clearSelection}}
                  @label="doc_categories.category_settings.index_editor.unindexed_topics.clear_selection"
                />
              {{/if}}
            </div>
          {{/if}}

          {{#if this.retryRequest}}
            <DButton
              class="btn-default btn-small doc-category-unindexed-topics__retry"
              @action={{this.retry}}
              @label="doc_categories.category_settings.index_editor.unindexed_topics.retry"
            />
          {{/if}}

          {{#if this.canLoadMore}}
            <DButton
              class="btn-default btn-small doc-category-unindexed-topics__load-more"
              @action={{this.loadMore}}
              @isLoading={{this.isLoading}}
              @label="doc_categories.category_settings.index_editor.unindexed_topics.load_more"
            />
          {{/if}}
        </Form>
      </:body>

      <:footer>
        <DButton
          class="btn-primary doc-category-unindexed-topics__add"
          @action={{this.add}}
          @disabled={{this.addDisabled}}
          @translatedLabel={{this.addLabel}}
        />
        <DModalCancel @close={{@closeModal}} />
        {{#if this.capacityMessage}}
          <span class="doc-category-unindexed-topics__capacity">
            {{this.capacityMessage}}
          </span>
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
