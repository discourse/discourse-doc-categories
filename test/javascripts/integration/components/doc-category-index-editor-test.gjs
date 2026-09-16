import { render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import DocCategoryIndexEditor from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-index-editor";

/**
 * The editor's own serialized shape: sections carry `text` and `links`, links
 * carry `text` and `href`. This is what the category serializer sends, not the
 * internal tracked shape the component builds from it.
 */
function indexData() {
  return [
    {
      text: "Getting started",
      links: [
        { text: "Install", href: "/t/install/1" },
        { text: "Configure", href: "/t/configure/2" },
      ],
    },
    {
      text: "Reference",
      links: [{ text: "API", href: "/t/api/3" }],
    },
  ];
}

/**
 * Renders the editor and hands back the component instance, which it publishes
 * through `@onRegisterEditor`. Driving the batch actions through the instance
 * keeps these tests about the selection algebra rather than about which button
 * carries which icon.
 */
async function renderEditor(data = indexData()) {
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

/** Every link across every section, in order. */
function allLinks(editor) {
  return editor.sections.flatMap((section) => section.links);
}

module(
  "Integration | Component | doc-category-index-editor | batch mode",
  function (hooks) {
    setupRenderingTest(hooks);

    test("it starts closed with nothing selected", async function (assert) {
      const editor = await renderEditor();

      assert.false(editor.batchMode, "batch mode is off");
      assert.strictEqual(editor.selectionCount, 0, "nothing is selected");
      assert.false(editor.hasSelection, "and it reports no selection");
    });

    test("closing with nothing selected needs no confirmation", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      const confirm = sinon.stub(dialog, "yesNoConfirm");

      editor.toggleBatchMode();
      await settled();
      editor.toggleBatchMode();
      await settled();

      assert.false(editor.batchMode, "it closes straight away");
      assert.false(confirm.called, "with nothing to lose, it does not ask");
    });

    test("closing with a live selection asks before discarding it", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      const confirm = sinon.stub(dialog, "yesNoConfirm");

      editor.toggleBatchMode();
      await settled();
      editor.selectAll();
      await settled();
      editor.toggleBatchMode();
      await settled();

      assert.true(confirm.calledOnce, "it asks first");
      assert.true(
        editor.batchMode,
        "and stays open until answered, so a mis-click cannot drop the selection"
      );
      assert.true(editor.hasSelection, "with the selection intact");
    });

    test("confirming the close drops the selection", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      sinon
        .stub(dialog, "yesNoConfirm")
        .callsFake(({ didConfirm }) => didConfirm());

      editor.toggleBatchMode();
      await settled();
      editor.selectAll();
      await settled();
      editor.toggleBatchMode();
      await settled();

      assert.false(editor.batchMode, "batch mode is off");
      assert.strictEqual(
        editor.selectionCount,
        0,
        "and the selection does not survive it"
      );
    });

    test("it stays shut for a single section with one link", async function (assert) {
      const editor = await renderEditor([
        { text: "Only", links: [{ text: "Alone", href: "/t/alone/1" }] },
      ]);

      assert.false(
        editor.canToggleBatchMode,
        "there is nothing a batch could do that a single row control cannot"
      );
    });

    test("it refuses to open while a row is being edited", async function (assert) {
      const editor = await renderEditor();

      editor.sections[0].links[0].isEditing = true;
      await settled();

      assert.false(
        editor.canToggleBatchMode,
        "an open edit blocks batch mode, so a half-typed row cannot be bulk deleted"
      );
    });

    test("it refuses to open with no sections", async function (assert) {
      const editor = await renderEditor([]);

      assert.false(editor.canToggleBatchMode, "there is nothing to select");
    });

    test("selectAll takes every link when no section is selected", async function (assert) {
      const editor = await renderEditor();

      editor.toggleBatchMode();
      await settled();
      editor.selectAll();
      await settled();

      assert.strictEqual(
        editor.selectedItems.size,
        3,
        "all three links across both sections"
      );
      assert.strictEqual(
        editor.selectedSections.size,
        0,
        "and no sections, because none was selected first"
      );
    });

    test("selectAll takes every section once one section is selected", async function (assert) {
      const editor = await renderEditor();

      editor.toggleBatchMode();
      await settled();
      editor.selectedSections.add(editor.sections[0]);
      editor.selectAll();
      await settled();

      assert.strictEqual(
        editor.selectedSections.size,
        2,
        "selecting a section switches selectAll to operating on sections"
      );
      assert.strictEqual(
        editor.selectedItems.size,
        0,
        "and it leaves links alone"
      );
    });

    test("invertSelection flips the links it has not got", async function (assert) {
      const editor = await renderEditor();
      const links = allLinks(editor);

      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(links[0]);
      editor.invertSelection();
      await settled();

      assert.false(
        editor.selectedItems.has(links[0]),
        "the selected link is dropped"
      );
      assert.true(editor.selectedItems.has(links[1]), "and the rest are taken");
      assert.true(editor.selectedItems.has(links[2]));
    });

    test("invertSelection flips sections when a section is selected", async function (assert) {
      const editor = await renderEditor();

      editor.toggleBatchMode();
      await settled();
      editor.selectedSections.add(editor.sections[0]);
      editor.invertSelection();
      await settled();

      assert.false(
        editor.selectedSections.has(editor.sections[0]),
        "the selected section is dropped"
      );
      assert.true(
        editor.selectedSections.has(editor.sections[1]),
        "and the other is taken"
      );
    });

    test("clearSelection empties both sets", async function (assert) {
      const editor = await renderEditor();

      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(allLinks(editor)[0]);
      editor.selectedSections.add(editor.sections[0]);
      editor.clearSelection();
      await settled();

      assert.strictEqual(editor.selectionCount, 0, "nothing is left selected");
    });

    test("a selection spanning links and sections reports as mixed", async function (assert) {
      const editor = await renderEditor();

      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(allLinks(editor)[0]);
      await settled();

      assert.false(editor.isMixedSelection, "links alone are not mixed");

      editor.selectedSections.add(editor.sections[0]);
      await settled();

      assert.true(
        editor.isMixedSelection,
        "links and sections together are mixed, which is what blocks a drag"
      );
      assert.strictEqual(editor.selectionCount, 2, "and both are counted");
    });

    test("bulkDelete asks before removing anything", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      const confirm = sinon.stub(dialog, "yesNoConfirm");

      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(allLinks(editor)[0]);
      editor.bulkDelete();
      await settled();

      assert.true(confirm.calledOnce, "it confirms first");
      assert.strictEqual(
        allLinks(editor).length,
        3,
        "and removes nothing until the reader agrees"
      );
    });

    test("bulkDelete removes only the selected links", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      sinon
        .stub(dialog, "yesNoConfirm")
        .callsFake(({ didConfirm }) => didConfirm());

      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(editor.sections[0].links[0]);
      editor.bulkDelete();
      await settled();

      assert.deepEqual(
        allLinks(editor).map((link) => link.title),
        ["Configure", "API"],
        "the selected link goes and the others keep their order across sections"
      );
      assert.strictEqual(
        editor.sections.length,
        2,
        "and no section is removed"
      );
    });

    test("bulkDelete removes a selected section with its links", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      sinon
        .stub(dialog, "yesNoConfirm")
        .callsFake(({ didConfirm }) => didConfirm());

      editor.toggleBatchMode();
      await settled();
      editor.selectedSections.add(editor.sections[0]);
      editor.bulkDelete();
      await settled();

      assert.deepEqual(
        editor.sections.map((section) => section.title),
        ["Reference"],
        "the selected section goes"
      );
      assert.deepEqual(
        allLinks(editor).map((link) => link.title),
        ["API"],
        "and takes its links with it"
      );
    });

    test("bulkDelete empties the selection once it has run", async function (assert) {
      const editor = await renderEditor();
      const dialog = this.owner.lookup("service:dialog");
      sinon
        .stub(dialog, "yesNoConfirm")
        .callsFake(({ didConfirm }) => didConfirm());

      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(allLinks(editor)[0]);
      editor.bulkDelete();
      await settled();

      assert.strictEqual(
        editor.selectionCount,
        0,
        "so the next delete cannot act on rows that are already gone"
      );
    });
  }
);

module(
  "Integration | Component | doc-category-index-editor | validation",
  function (hooks) {
    setupRenderingTest(hooks);

    test("it finds links sharing an href across sections", async function (assert) {
      const editor = await renderEditor([
        { text: "One", links: [{ text: "A", href: "/t/same/1" }] },
        { text: "Two", links: [{ text: "B", href: "/t/same/1" }] },
      ]);

      assert.deepEqual(
        [...editor.duplicateHrefs],
        ["/t/same/1"],
        "a duplicate counts across sections, not only within one"
      );
    });

    test("it ignores links with no href", async function (assert) {
      const editor = await renderEditor([
        {
          text: "One",
          links: [
            { text: "A", href: "" },
            { text: "B", href: "" },
          ],
        },
      ]);

      assert.strictEqual(
        editor.duplicateHrefs.size,
        0,
        "two unfinished rows are not duplicates of each other"
      );
    });

    test("duplicate section titles are matched case insensitively", async function (assert) {
      const editor = await renderEditor([
        { text: "Reference", links: [{ text: "A", href: "/a" }] },
        { text: "reference", links: [{ text: "B", href: "/b" }] },
      ]);

      assert.deepEqual(
        [...editor.duplicateTitles],
        ["reference"],
        "casing does not make two sections distinct to a reader"
      );
    });

    test("duplicate hrefs are matched exactly", async function (assert) {
      const editor = await renderEditor([
        { text: "One", links: [{ text: "A", href: "/t/Same/1" }] },
        { text: "Two", links: [{ text: "B", href: "/t/same/1" }] },
      ]);

      assert.strictEqual(
        editor.duplicateHrefs.size,
        0,
        "unlike titles, a URL that differs in case is a different URL"
      );
    });

    test("a row left open counts as a validation error", async function (assert) {
      const editor = await renderEditor();

      assert.deepEqual(editor.validationErrors, [], "nothing is wrong yet");

      editor.sections[0].links[0].isEditing = true;
      await settled();

      assert.strictEqual(
        editor.validationErrors.length,
        1,
        "an unfinished row blocks the save rather than being silently dropped"
      );
    });

    test("Apply stays disabled until something has actually changed", async function (assert) {
      const editor = await renderEditor();

      assert.true(
        editor.applyDisabled,
        "there is nothing to apply on a freshly opened editor"
      );
    });

    test("Apply is disabled while a validation error stands", async function (assert) {
      const editor = await renderEditor();

      editor._hasLocalChanges = true;
      await settled();
      assert.false(editor.applyDisabled, "a pending change enables it");

      editor.sections[0].links[0].isEditing = true;
      await settled();

      assert.true(
        editor.applyDisabled,
        "and an open row disables it again, even with changes to save"
      );
    });

    test("Apply is disabled while a save is in flight", async function (assert) {
      const editor = await renderEditor();

      editor._hasLocalChanges = true;
      editor.saveState = "saving";
      await settled();

      assert.true(editor.applyDisabled, "so a double click cannot save twice");
      assert.strictEqual(
        editor.applyLabel,
        "doc_categories.category_settings.index_editor.applying",
        "and the label says so"
      );
    });

    test("an untitled section past the first opens for naming", async function (assert) {
      await renderEditor([
        { text: "", links: [{ text: "A", href: "/a" }] },
        { text: "", links: [{ text: "B", href: "/b" }] },
      ]);

      assert
        .dom(".doc-category-index-editor__section-title")
        .exists(
          { count: 1 },
          "only the second opens: the first is allowed to stay untitled"
        );
      assert
        .dom(".doc-category-index-editor__validation-error")
        .doesNotExist("and a section still being named is not yet an error");
    });

    test("an untitled section becomes an error once naming is dismissed", async function (assert) {
      const editor = await renderEditor([
        { text: "", links: [{ text: "A", href: "/a" }] },
        { text: "", links: [{ text: "B", href: "/b" }] },
      ]);

      editor.sections[1].isEditingTitle = false;
      await settled();

      assert
        .dom(".doc-category-index-editor__validation-error")
        .exists(
          { count: 1 },
          "leaving it blank is what makes it wrong, not opening it"
        );
    });

    test("the first section stays untitled without complaint", async function (assert) {
      const editor = await renderEditor([
        { text: "", links: [{ text: "A", href: "/a" }] },
      ]);

      assert
        .dom(".doc-category-index-editor__section-title")
        .doesNotExist("it does not open for naming");
      assert
        .dom(".doc-category-index-editor__validation-error")
        .doesNotExist(
          "and never complains: a leading section needs no heading"
        );
      assert.deepEqual(
        editor.validationErrors,
        [],
        "so nothing blocks the save"
      );
    });
  }
);
