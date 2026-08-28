import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import DocIndexModeState from "discourse/plugins/discourse-doc-categories/discourse/lib/doc-index-mode-state";

function buildState(category) {
  return new DocIndexModeState({
    category,
    form: {},
    getTransientData: () => ({}),
    dialog: {},
    owner: {},
  });
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
});
