import { tracked } from "@glimmer/tracking";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { click, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import DocCategoryIndexEditor from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-index-editor";

const TOGGLE = ".doc-category-index-editor__toggle-all-sections";
const COLLAPSED = ".doc-category-index-editor__section-body.--collapsed";

module(
  "Integration | Component | DocCategoryIndexEditor | collapse all",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      pretender.post("/doc-categories/indexes/1/unindexed_topics", () =>
        response({ topics: [], total_count: 0, page: 0, per_page: 50 })
      );
      this.toolbar = tracked(undefined);
      this.setToolbar = (element) => (this.toolbar.value = element);
      this.indexData = [
        {
          text: "Getting started",
          links: [{ text: "Install", href: "/t/install/1" }],
        },
        { text: "Reference", links: [{ text: "API", href: "/t/api/2" }] },
      ];
    });

    test("toggles all sections without changing the saved index", async function (assert) {
      let editor;
      const capture = (instance) => (editor = instance);
      await render(
        <template>
          <div {{didInsert this.setToolbar}}></div>
          <DocCategoryIndexEditor
            @toolbarElement={{this.toolbar.value}}
            @categoryId={{1}}
            @indexData={{this.indexData}}
            @onRegisterEditor={{capture}}
          />
        </template>
      );
      const serialized = editor.serializedSections;

      assert
        .dom(TOGGLE)
        .hasAttribute(
          "title",
          i18n("sidebar.collapse_all_sections"),
          "offers to collapse the expanded index"
        );
      assert
        .dom(`${TOGGLE} .d-icon-angles-up`)
        .exists("uses the sidebar collapse icon");
      await click(TOGGLE);
      assert.dom(COLLAPSED).exists({ count: 2 }, "collapses every section");
      assert
        .dom(TOGGLE)
        .hasAttribute(
          "title",
          i18n("sidebar.expand_all_sections"),
          "offers to expand the collapsed index"
        );
      assert
        .dom(`${TOGGLE} .d-icon-angles-down`)
        .exists("uses the sidebar expand icon");
      assert.strictEqual(
        editor.serializedSections,
        serialized,
        "collapse state is not serialized"
      );
      assert.true(editor.applyDisabled, "collapsing does not enable Apply");

      await click(TOGGLE);
      assert.dom(COLLAPSED).doesNotExist("expands every section");
      assert.true(editor.applyDisabled, "expanding does not enable Apply");
    });

    test("expands all when only some sections are collapsed", async function (assert) {
      await render(
        <template>
          <div {{didInsert this.setToolbar}}></div>
          <DocCategoryIndexEditor
            @toolbarElement={{this.toolbar.value}}
            @categoryId={{1}}
            @indexData={{this.indexData}}
          />
        </template>
      );
      await click(".doc-category-index-editor__collapse-btn");
      assert.dom(COLLAPSED).exists({ count: 1 }, "starts with a mixed state");
      assert
        .dom(TOGGLE)
        .hasAttribute(
          "title",
          i18n("sidebar.expand_all_sections"),
          "matches the sidebar's mixed-state behavior"
        );
      await click(TOGGLE);
      assert
        .dom(COLLAPSED)
        .doesNotExist(
          "opens all sections rather than closing the remaining one"
        );
    });

    test("disables the toggle for an empty index", async function (assert) {
      await render(
        <template>
          <div {{didInsert this.setToolbar}}></div><DocCategoryIndexEditor
            @toolbarElement={{this.toolbar.value}}
            @categoryId={{1}}
          />
        </template>
      );
      assert.dom(TOGGLE).isDisabled("there are no sections to toggle");
    });
  }
);
