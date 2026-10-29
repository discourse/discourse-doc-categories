import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
import DocCategoryIndexEditor from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-index-editor";
import {
  MAX_LINKS_PER_SECTION,
  MAX_SECTIONS,
} from "discourse/plugins/discourse-doc-categories/discourse/lib/constants";

const PREFIX = "doc_categories.category_settings.index_editor";

function links(count) {
  return Array.from({ length: count }, (_, index) => ({
    text: `Link ${index}`,
    href: `/link-${index}`,
  }));
}

async function renderEditor(data) {
  let editor;
  const capture = (instance) => (editor = instance);
  await render(
    <template>
      <DocCategoryIndexEditor
        @categoryId={{1}}
        @indexData={{data}}
        @onRegisterEditor={{capture}}
      />
    </template>
  );
  return editor;
}

module(
  "Integration | Component | doc-category-index-editor | capacity",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(() => {
      pretender.post("/doc-categories/indexes/1/unindexed_topics", () =>
        response({ topics: [], total_count: 0, page: 0, per_page: 50 })
      );
    });

    test("section additions stop at the limit and resume when a section is removed", async function (assert) {
      const editor = await renderEditor(
        Array.from({ length: MAX_SECTIONS }, (_, index) => ({
          text: `Section ${index}`,
          links: links(1),
        }))
      );

      assert
        .dom(".doc-category-index-editor__footer .d-combo-button-button")
        .isDisabled();
      assert
        .dom(
          ".doc-category-index-editor__footer .doc-category-index-editor__capacity-message"
        )
        .hasText(i18n(`${PREFIX}.section_limit`, { count: MAX_SECTIONS }));
      await click(".doc-category-index-editor__footer .d-combo-button-menu");
      assert
        .dom(".fk-d-menu__inner-content button", document)
        .isDisabled("auto-index cannot bypass the limit");
      editor.addSection();
      editor.addAutoIndexSection();
      assert.strictEqual(editor.sections.length, MAX_SECTIONS);

      editor.sections.pop();
      await settled();
      assert
        .dom(".doc-category-index-editor__footer .d-combo-button-button")
        .isEnabled();
      editor.addAutoIndexSection();
      await settled();
      assert.strictEqual(editor.sections.length, MAX_SECTIONS);
      assert.true(editor.hasAutoIndexSection);
    });

    test("topic and manual-link additions stop at the link limit", async function (assert) {
      const editor = await renderEditor([
        { text: "Full", links: links(MAX_LINKS_PER_SECTION) },
      ]);
      const add =
        ".doc-category-index-editor__section-actions .d-combo-button-button";
      const menu =
        ".doc-category-index-editor__section-actions .d-combo-button-menu";
      assert.dom(add).isDisabled();
      assert
        .dom(
          ".doc-category-index-editor__section-actions .doc-category-index-editor__capacity-message"
        )
        .hasText(
          i18n(`${PREFIX}.link_limit`, { count: MAX_LINKS_PER_SECTION })
        );
      await click(menu);
      assert.dom(".fk-d-menu__inner-content button", document).isDisabled();

      editor.sections[0].links.pop();
      await settled();
      assert.dom(add).isEnabled();
      await click(".fk-d-menu__inner-content button");
      assert.strictEqual(
        editor.sections[0].links.length,
        MAX_LINKS_PER_SECTION
      );
      assert.dom(add).isDisabled();
    });

    test("a batch move refuses overflow atomically but permits reordering a full section", async function (assert) {
      const editor = await renderEditor([
        { text: "Source", links: links(2) },
        { text: "Destination", links: links(MAX_LINKS_PER_SECTION) },
      ]);
      const [source, destination] = editor.sections;
      const original = [...destination.links];
      editor.selectedItems.add(source.links[0]);
      editor.selectedItems.add(destination.links[0]);
      editor.batchReorderItems(null, destination, false);
      await settled();
      assert.strictEqual(
        source.links.length,
        2,
        "refused move preserves the source"
      );
      assert.deepEqual(
        [...destination.links],
        original,
        "refused move preserves the destination order"
      );
      assert.strictEqual(
        editor.selectedItems.size,
        2,
        "selection remains available for another destination"
      );
      assert.false(editor.hasPendingChanges);

      destination.links.pop();
      editor.batchReorderItems(null, destination, false);
      await settled();
      assert.strictEqual(source.links.length, 1);
      assert.strictEqual(
        destination.links.length,
        MAX_LINKS_PER_SECTION,
        "only incoming links consume capacity"
      );

      editor.selectedItems.clear();
      const first = destination.links[0];
      editor.selectedItems.add(first);
      editor.batchReorderItems(null, destination, false);
      await settled();
      assert.strictEqual(
        destination.links.at(-1),
        first,
        "reordering at capacity remains allowed"
      );
      assert.strictEqual(destination.links.length, MAX_LINKS_PER_SECTION);
    });

    test("an oversized restored draft cannot be applied", async function (assert) {
      const save = sinon.spy();
      pretender.put("/doc-categories/indexes/1", () => {
        save();
        return response({});
      });
      const editor = await renderEditor([
        { text: "Oversized", links: links(MAX_LINKS_PER_SECTION + 1) },
      ]);
      assert.true(
        editor.validationErrors.includes(
          i18n(`${PREFIX}.link_limit`, { count: MAX_LINKS_PER_SECTION })
        )
      );
      editor.addSection();
      await settled();
      assert.dom(".doc-category-index-editor__apply-btn").isDisabled();
      await editor.apply();
      assert.false(save.called, "no invalid request reaches the server");
    });
  }
);
