import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import { i18n } from "discourse-i18n";
import DocIndexModeState from "discourse/plugins/discourse-doc-categories/discourse/lib/doc-index-mode-state";

/**
 * The collaborators the state writes through. `form` records what it would send
 * to FormKit; `dialog` records whether it asked before destroying anything, and
 * answers yes only when `confirm` is set.
 */
function buildCollaborators({ confirm = false } = {}) {
  const form = {
    writes: [],
    set: (key, value) => form.writes.push([key, value]),
  };
  const dialog = {
    asked: [],
    yesNoConfirm(options) {
      dialog.asked.push(options);
      if (confirm) {
        options.didConfirm();
      }
    },
  };
  return { form, dialog };
}

/** A closed menu is the one thing every switch does before anything else. */
function buildMenu() {
  const menu = { closed: 0, close: () => menu.closed++ };
  return menu;
}

function buildState(category, { transientData = {}, ...options } = {}) {
  const { form, dialog } = buildCollaborators(options);
  const state = new DocIndexModeState({
    category,
    form,
    getTransientData: () => transientData,
    dialog,
    owner: {},
  });
  state.form = form;
  state.dialog = dialog;
  return state;
}

module("Unit | Lib | doc-index-mode-state", function (hooks) {
  setupTest(hooks);

  test("a category with no index and no ancestor index inherits nothing", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: null });

    assert.true(state.isNoneMode, "sits in the disabled mode");
    assert.strictEqual(
      state.inheritedIndexCategory,
      null,
      "reports no category to inherit from"
    );
  });

  test("a subcategory with no index of its own inherits its parent's", function (assert) {
    const parent = {
      id: 1,
      name: "Mathematics",
      doc_index_topic_id: 7,
      doc_category_index: { sections: [] },
    };
    const state = buildState({
      id: 2,
      name: "Calculus",
      doc_index_topic_id: null,
      parentCategory: parent,
    });

    assert.true(state.isNoneMode, "still has no index of its own");
    assert.strictEqual(
      state.inheritedIndexCategory,
      parent,
      "names the ancestor whose index it shows"
    );
  });

  test("it walks past an ancestor that has no index of its own", function (assert) {
    const grandparent = {
      id: 1,
      name: "Mathematics",
      doc_category_index: { sections: [] },
    };
    const parent = {
      id: 2,
      name: "Analysis",
      doc_index_topic_id: null,
      parentCategory: grandparent,
    };
    const state = buildState({
      id: 3,
      name: "Calculus",
      doc_index_topic_id: null,
      parentCategory: parent,
    });

    assert.strictEqual(
      state.inheritedIndexCategory,
      grandparent,
      "skips the ancestor that carries no index"
    );
  });

  test("a category with its own index inherits nothing", function (assert) {
    const parent = {
      id: 1,
      name: "Mathematics",
      doc_category_index: { sections: [] },
    };
    const state = buildState({
      id: 2,
      doc_index_topic_id: -1,
      parentCategory: parent,
    });

    assert.true(state.isDirectMode, "uses its own index");
    assert.strictEqual(
      state.inheritedIndexCategory,
      null,
      "so the ancestor's is not what it shows"
    );
  });

  test("a positive topic id starts in topic mode", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });

    assert.true(state.isTopicMode);
    assert.strictEqual(state.indexTopicId, 7, "and exposes the topic");
  });

  test("the -1 sentinel starts in direct mode, not topic mode", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: -1 });

    assert.true(state.isDirectMode, "-1 means an inline index, not topic -1");
    assert.strictEqual(
      state.indexTopicId,
      null,
      "so there is no topic to point at"
    );
  });

  test("transient form data wins over the saved category", function (assert) {
    const state = buildState(
      { id: 1, doc_index_topic_id: 7 },
      { transientData: { doc_index_topic_id: -1 } }
    );

    assert.true(
      state.isDirectMode,
      "an unsaved edit decides the mode, so reopening the tab does not revert it"
    );
  });

  test("the mode label follows the mode", function (assert) {
    assert.strictEqual(
      buildState({ id: 1, doc_index_topic_id: 7 }).currentModeLabel,
      i18n("doc_categories.category_settings.index_editor.mode_topic")
    );
    assert.strictEqual(
      buildState({ id: 1, doc_index_topic_id: -1 }).currentModeLabel,
      i18n("doc_categories.category_settings.index_editor.mode_direct")
    );
    assert.strictEqual(
      buildState({ id: 1, doc_index_topic_id: null }).currentModeLabel,
      i18n("doc_categories.category_settings.index_editor.mode_none")
    );
  });

  test("topic search is scoped to the category once it has an id", function (assert) {
    assert.strictEqual(
      buildState({ id: 42 }).searchFilters,
      "in:title include:unlisted category:=42"
    );
    assert.strictEqual(
      buildState({}).searchFilters,
      "in:title include:unlisted",
      "an unsaved category cannot scope, so it searches everywhere"
    );
  });

  test("it reports a topic that could not be loaded", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });
    state.loadingIndexTopic = false;

    assert.strictEqual(
      state.topicErrorMessage,
      i18n(
        "doc_categories.category_settings.index_topic.errors.topic_not_found"
      )
    );
  });

  test("it says nothing while the topic is still loading", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });

    assert.strictEqual(
      state.topicErrorMessage,
      undefined,
      "a topic in flight is not a missing topic"
    );
  });

  test("it reports a topic belonging to another category", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });
    state.loadingIndexTopic = false;
    state.indexTopic = { category_id: 2, category: { name: "Elsewhere" } };

    assert.strictEqual(
      state.topicErrorMessage,
      i18n(
        "doc_categories.category_settings.index_topic.errors.mismatched_category",
        { category_name: "Elsewhere" }
      )
    );
  });

  test("switching to the mode it is already in does nothing", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: null });
    const menu = buildMenu();

    state.switchToNoneMode(menu);

    assert.strictEqual(menu.closed, 1, "the menu still closes");
    assert.deepEqual(state.form.writes, [], "but nothing is written");
    assert.deepEqual(state.dialog.asked, [], "and nothing is asked");
  });

  test("switching to disabled with nothing to lose does not ask", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: -1 });
    const menu = buildMenu();

    state.switchToDirectMode(menu);
    state.form.writes.length = 0;
    state.switchToNoneMode(buildMenu());

    assert.deepEqual(state.dialog.asked, [], "there is no index to destroy");
    assert.true(state.isNoneMode);
  });

  test("switching to disabled with an index asks first and holds", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });

    state.switchToNoneMode(buildMenu());

    assert.strictEqual(state.dialog.asked.length, 1, "it asks");
    assert.true(state.isTopicMode, "and stays put until answered");
    assert.deepEqual(state.form.writes, [], "writing nothing meanwhile");
  });

  test("confirming the switch to disabled clears both fields", function (assert) {
    const state = buildState(
      { id: 1, doc_index_topic_id: 7 },
      { confirm: true }
    );

    state.switchToNoneMode(buildMenu());

    assert.true(state.isNoneMode);
    assert.deepEqual(
      state.form.writes,
      [
        ["doc_index_topic_id", null],
        ["doc_index_sections", "[]"],
      ],
      "an empty array, not null, because that is what clears the stored index"
    );
  });

  test("switching to the editor from disabled does not ask", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: null });

    state.switchToDirectMode(buildMenu());

    assert.deepEqual(state.dialog.asked, [], "there is no topic to disconnect");
    assert.true(state.isDirectMode);
    assert.deepEqual(state.form.writes, [["doc_index_topic_id", -1]]);
  });

  test("switching to the editor from a topic asks first", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });

    state.switchToDirectMode(buildMenu());

    assert.strictEqual(
      state.dialog.asked.length,
      1,
      "the topic would be disconnected, so it asks"
    );
    assert.true(state.isTopicMode, "and holds until answered");
  });

  test("switching to a topic asks only when sections would be overwritten", function (assert) {
    const withSections = buildState({
      id: 1,
      doc_index_topic_id: -1,
      doc_category_index: [{ text: "Section" }],
    });
    withSections.switchToTopicMode(buildMenu());

    assert.strictEqual(
      withSections.dialog.asked.length,
      1,
      "sections are at risk"
    );
    assert.true(withSections.isDirectMode, "so it holds");

    const empty = buildState({
      id: 1,
      doc_index_topic_id: -1,
      doc_category_index: [],
    });
    empty.switchToTopicMode(buildMenu());

    assert.deepEqual(empty.dialog.asked, [], "an empty index is not at risk");
    assert.true(empty.isTopicMode, "so it switches straight away");
  });

  test("confirming the switch to a topic clears the inline index", function (assert) {
    const state = buildState(
      { id: 1, doc_index_topic_id: -1, doc_category_index: [{ text: "S" }] },
      { confirm: true }
    );

    state.switchToTopicMode(buildMenu());

    assert.true(state.isTopicMode);
    assert.deepEqual(
      state.form.writes,
      [
        ["doc_index_topic_id", null],
        ["doc_index_sections", null],
      ],
      "null, not an empty array, because the topic owns the index from here"
    );
  });

  test("choosing a topic records it and its id", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: null });
    const topic = { id: 9, title: "Index" };

    state.onChangeIndexTopic(9, topic);

    assert.strictEqual(state.indexTopic, topic);
    assert.deepEqual(state.indexTopicContent, [topic], "the chooser's content");
    assert.deepEqual(state.form.writes, [["doc_index_topic_id", 9]]);
  });

  test("clearing the topic empties the chooser", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: 7 });

    state.onChangeIndexTopic(null, null);

    assert.deepEqual(
      state.indexTopicContent,
      [],
      "so the chooser does not keep offering the topic that was dropped"
    );
  });

  test("reset returns to the saved mode and drops the loaded topic", function (assert) {
    const state = buildState({ id: 1, doc_index_topic_id: null });
    state.switchToDirectMode(buildMenu());
    state.indexTopic = { id: 9 };
    state.indexTopicContent = [{ id: 9 }];

    state.reset();

    assert.true(state.isNoneMode, "back to what the category actually has");
    assert.strictEqual(state.indexTopic, null);
    assert.deepEqual(state.indexTopicContent, []);
  });
});
