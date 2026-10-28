import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import { i18n } from "discourse-i18n";
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

/**
 * Answers the unindexed-topics count the editor asks for on mount, and
 * records each request body so a test can see what was asked.
 */
function stubUnindexedTopics(count = 0) {
  const requests = [];
  pretender.post("/doc-categories/indexes/1/unindexed_topics", (request) => {
    requests.push(JSON.parse(request.requestBody));
    return response({
      topics: [],
      total_count: count,
      page: 0,
      per_page: 50,
    });
  });
  return requests;
}

module(
  "Integration | Component | doc-category-index-editor | batch mode",
  function (hooks) {
    setupRenderingTest(hooks);
    hooks.beforeEach(() => stubUnindexedTopics());

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

    test("applying empties the selection it has rebuilt the rows under", async function (assert) {
      // The server's answer renames a link, so the rebuild is observable and
      // the cleared selection cannot be mistaken for a refresh that never ran.
      pretender.put("/doc-categories/indexes/1", () =>
        response({
          index_structure: [
            {
              text: "Getting started",
              links: [
                { text: "Installation", href: "/t/install/1" },
                { text: "Configure", href: "/t/configure/2" },
              ],
            },
            { text: "Reference", links: [{ text: "API", href: "/t/api/3" }] },
          ],
        })
      );

      const editor = await renderEditor();
      editor.toggleBatchMode();
      await settled();
      editor.selectedItems.add(allLinks(editor)[0]);
      editor._hasLocalChanges = true;
      await settled();
      assert.strictEqual(editor.selectionCount, 1, "a link is selected");

      await editor.apply();
      await settled();

      assert.deepEqual(
        allLinks(editor).map((link) => link.title),
        ["Installation", "Configure", "API"],
        "the rows are the ones the server sent back, not the selected objects"
      );
      assert.strictEqual(
        editor.selectionCount,
        0,
        "so the bar cannot report a selection none of the rows show"
      );
      assert.true(
        editor.batchMode,
        "and the reader is left in batch mode, just with nothing selected"
      );
    });
  }
);

module(
  "Integration | Component | doc-category-index-editor | validation",
  function (hooks) {
    setupRenderingTest(hooks);
    hooks.beforeEach(() => stubUnindexedTopics());

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

const UNINDEXED =
  "doc_categories.category_settings.index_editor.unindexed_topics";

/** Saved sections with topic links, a manual topic URL and an external URL. */
function topicIndexData() {
  return [
    {
      id: 10,
      text: "Start here",
      links: [{ text: "Install", href: "/t/install/1", topic_id: 1 }],
    },
    {
      id: 11,
      text: "Reference",
      links: [
        { text: "External", href: "https://example.com/reference" },
        { text: "Guide", href: "/t/guide/5" },
      ],
    },
  ];
}

async function renderTopicEditor(
  data = topicIndexData(),
  category,
  registerAfterReset
) {
  let editor;
  const capture = (instance) => (editor = instance);

  await render(
    <template>
      <DocCategoryIndexEditor
        @category={{category}}
        @categoryId={{1}}
        @indexData={{data}}
        @onRegisterEditor={{capture}}
        @registerAfterReset={{registerAfterReset}}
      />
    </template>
  );

  return editor;
}

function topic(id) {
  return { id, title: `Topic ${id}`, slug: `topic-${id}`, category_id: 1 };
}

module(
  "Integration | Component | doc-category-index-editor | unindexed topics",
  function (hooks) {
    setupRenderingTest(hooks);

    test("counts this category's topics that the draft leaves out", async function (assert) {
      const requests = stubUnindexedTopics(3);
      await renderTopicEditor();

      assert.deepEqual(
        requests,
        [
          {
            exclude_topic_ids: [1],
            exclude_hrefs: ["/t/guide/5"],
            include_subcategories: false,
            page: 0,
            limit: 0,
          },
        ],
        "it asks once for a count, sending links without a topic id as hrefs"
      );
      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(i18n(`${UNINDEXED}.count`, { count: 3 }));
    });

    test("shows nothing when every topic is in the index", async function (assert) {
      stubUnindexedTopics(0);
      await renderTopicEditor();

      assert
        .dom(".doc-category-index-editor__missing-topics")
        .doesNotExist("there is nothing to advise about");
    });

    test("recounts only when the draft's topics change", async function (assert) {
      const requests = stubUnindexedTopics(3);
      const editor = await renderTopicEditor();

      editor.applySectionMove({
        proposedFromItems: [editor.sections[1], editor.sections[0]],
      });
      editor.sections[0].title = "Renamed";
      editor._saveToTransientData();
      await settled();

      assert.strictEqual(
        requests.length,
        1,
        "reordering and retitling point at the same topics"
      );

      editor.sections[0].links.splice(1, 1);
      editor._saveToTransientData();
      await settled();

      assert.strictEqual(requests.length, 2, "removing a link does not");
      assert.deepEqual(
        requests[1].exclude_hrefs,
        [],
        "neither the removed topic nor the external link is excluded"
      );
    });

    test("counts in the auto-index scope when it includes subcategories", async function (assert) {
      const requests = stubUnindexedTopics(2);
      await renderTopicEditor(
        [
          ...topicIndexData(),
          { id: 12, text: "Other topics", auto_index: true, links: [] },
        ],
        { doc_category_auto_index_include_subcategories: true }
      );

      assert.true(requests[0].include_subcategories);
      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(
          i18n(`${UNINDEXED}.count_with_subcategories`, { count: 2 })
        );
    });

    test("a saved auto-index section still reports gaps", async function (assert) {
      stubUnindexedTopics(2);
      await renderTopicEditor([
        ...topicIndexData(),
        { id: 12, text: "Other topics", auto_index: true, links: [] },
      ]);

      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(
          i18n(`${UNINDEXED}.count`, { count: 2 }),
          "auto-index only collects new topics, so older ones can stay out"
        );
    });

    test("defers to auto-index when Apply will run it", async function (assert) {
      stubUnindexedTopics(2);
      const editor = await renderTopicEditor();

      editor.addAutoIndexSection();
      await settled();

      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(
          i18n(`${UNINDEXED}.auto_index_pending`, { count: 2 }),
          "a new auto-index section collects them on Apply"
        );
    });

    test("pending auto-index accounts for limited and exhausted capacity", async function (assert) {
      stubUnindexedTopics(3);
      const links = Array.from({ length: 199 }, (_, index) => ({
        text: `Topic ${index}`,
        href: `/t/topic/${index + 1}`,
        topic_id: index + 1,
      }));
      const editor = await renderTopicEditor([
        { id: 12, text: "Other topics", auto_index: true, links },
      ]);
      editor.pendingResync = true;
      await settled();

      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(
          i18n(`${UNINDEXED}.auto_index_pending`, { count: 1 }),
          "only available slots are promised"
        );
      editor.sections[0].links.push({
        title: "Last slot",
        href: "/t/last/999",
        topic_id: 999,
      });
      editor._saveToTransientData();
      await settled();
      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(
          i18n(`${UNINDEXED}.auto_index_full`),
          "a full auto-index section does not promise additions"
        );
    });

    test("Reset restores auto-index flags before recounting and a later Apply", async function (assert) {
      const requests = stubUnindexedTopics(3);
      let reset;
      let payload;
      pretender.put("/doc-categories/indexes/1", (request) => {
        payload = JSON.parse(request.requestBody);
        return response({ index_structure: topicIndexData() });
      });
      const editor = await renderTopicEditor(
        [
          ...topicIndexData(),
          { id: 12, text: "Other topics", auto_index: true, links: [] },
        ],
        {
          doc_category_auto_index_include_subcategories: false,
          set: sinon.stub(),
        },
        (callback) => {
          reset = callback;
        }
      );
      editor.autoIndexIncludeSubcategories = true;
      editor.pendingResync = true;
      editor._saveToTransientData();
      await settled();
      reset();
      await settled();

      assert.false(
        editor.autoIndexIncludeSubcategories,
        "the saved scope is restored"
      );
      assert.false(
        editor.pendingResync,
        "the discarded resync request is cleared"
      );
      assert.false(
        requests.at(-1).include_subcategories,
        "the recount uses the restored scope"
      );
      assert
        .dom(".doc-category-index-editor__missing-topics")
        .includesText(
          i18n(`${UNINDEXED}.count`, { count: 3 }),
          "the tip no longer claims a sync is pending"
        );
      assert.true(
        editor.applyDisabled,
        "Reset leaves no local changes to apply"
      );

      editor.addUnindexedTopics({ topics: [topic(7)], destination: "10" });
      await editor.apply();
      assert.false(
        payload.auto_index_include_subcategories,
        "later edits do not save the discarded scope"
      );
      assert.false(
        payload.force_sync,
        "later edits do not request the discarded resync"
      );
    });

    test("Review topics preselects the last manual section", async function (assert) {
      stubUnindexedTopics(2);
      const modal = this.owner.lookup("service:modal");
      const show = sinon.stub(modal, "show");
      await renderTopicEditor([
        ...topicIndexData(),
        { id: 12, text: "Other topics", auto_index: true, links: [] },
      ]);

      await click(".doc-category-index-editor__review-topics");

      const { model } = show.firstCall.args[1];
      assert.deepEqual(
        model.destinations.map((option) => option.value),
        ["10", "11", "new"],
        "manual sections and a new section are offered, but auto-index is not"
      );
      assert.strictEqual(model.initialDestination, "11");
      assert.false(model.includeSubcategories, "the scope matches the count");
      assert.deepEqual(
        model.getReferences(),
        {
          topicIds: [1],
          hrefs: ["/t/guide/5"],
        },
        "and the picker excludes what the whole draft points at"
      );
    });

    test("a section's own entry preselects that section", async function (assert) {
      stubUnindexedTopics(2);
      const modal = this.owner.lookup("service:modal");
      const show = sinon.stub(modal, "show");
      const editor = await renderTopicEditor();

      editor.reviewUnindexedTopics(editor.sections[0]);

      assert.strictEqual(show.firstCall.args[1].model.initialDestination, "10");
    });

    test("adding skips topics the draft already holds", async function (assert) {
      stubUnindexedTopics(2);
      const editor = await renderTopicEditor();

      const result = editor.addUnindexedTopics({
        topics: [topic(1), topic(5), topic(7)],
        destination: "10",
      });
      await settled();

      assert.deepEqual(result, { added: 1 }, "1 by id, 5 by its topic URL");
      assert.deepEqual(
        editor.sections[0].links.map((link) => link.href),
        ["/t/install/1", "/t/topic-7/7"],
        "the new link goes after the existing ones"
      );
      assert
        .dom(".doc-category-index-editor__added-topics")
        .includesText(
          i18n(`${UNINDEXED}.added`, { count: 1, section: "Start here" })
        );
    });

    test("undo takes back exactly the added links", async function (assert) {
      stubUnindexedTopics(2);
      const editor = await renderTopicEditor();

      editor.addUnindexedTopics({
        topics: [topic(7), topic(8)],
        destination: "10",
      });
      await settled();
      // Moved after adding: undo follows the objects, not their old place.
      const moved = editor.sections[0].links.pop();
      editor.sections[1].links.push(moved);
      await settled();

      await click(".doc-category-index-editor__undo-add");

      assert.deepEqual(
        allLinks(editor).map((link) => link.title),
        ["Install", "External", "Guide"]
      );
      assert
        .dom(".doc-category-index-editor__added-topics")
        .doesNotExist("there is nothing left to undo");
    });

    test("with no manual section, a new one goes before auto-index", async function (assert) {
      stubUnindexedTopics(2);
      const modal = this.owner.lookup("service:modal");
      const show = sinon.stub(modal, "show");
      const editor = await renderTopicEditor([
        { id: 12, text: "Other topics", auto_index: true, links: [] },
      ]);

      editor.reviewUnindexedTopics();
      const { model } = show.firstCall.args[1];
      assert.deepEqual(
        model.destinations.map((option) => option.value),
        ["new"]
      );

      model.addTopics({ topics: [topic(7)], destination: "new" });
      await settled();

      assert.deepEqual(
        editor.sections.map((section) => section.title),
        [
          i18n(
            "doc_categories.category_settings.index_editor.all_topics_section"
          ),
          "Other topics",
        ]
      );
    });

    test("full destinations offer a new section with a unique title", async function (assert) {
      stubUnindexedTopics(2);
      const base = i18n(
        "doc_categories.category_settings.index_editor.all_topics_section"
      );
      const links = Array.from({ length: 200 }, (_, index) => ({
        text: `Link ${index}`,
        href: `/l/${index}`,
      }));
      const modal = this.owner.lookup("service:modal");
      const show = sinon.stub(modal, "show");
      const editor = await renderTopicEditor([{ id: 10, text: base, links }]);
      editor.reviewUnindexedTopics();
      const { model } = show.firstCall.args[1];

      assert.deepEqual(
        model.destinations.map((option) => option.value),
        ["10", "new"],
        "a full section is not a dead end"
      );
      const result = model.addTopics({
        topics: [topic(7)],
        destination: "new",
      });
      await settled();
      assert.strictEqual(
        result.added,
        1,
        "the new destination accepts the reviewed topic"
      );
      assert.strictEqual(
        editor.sections[1].title,
        i18n(`${UNINDEXED}.numbered_section`, { title: base, count: 2 }),
        "the editor does not create a duplicate section title"
      );
    });

    test("new-section capacity errors name the same unique title offered in the picker", async function (assert) {
      stubUnindexedTopics(2);
      const base = i18n(
        "doc_categories.category_settings.index_editor.all_topics_section"
      );
      const editor = await renderTopicEditor([
        { id: 10, text: base, links: [] },
      ]);
      const result = editor.addUnindexedTopics({
        topics: Array.from({ length: 201 }, (_, index) => topic(index + 1000)),
        destination: "new",
      });
      const title = i18n(`${UNINDEXED}.numbered_section`, {
        title: base,
        count: 2,
      });
      assert.strictEqual(
        result.error,
        i18n(`${UNINDEXED}.section_room`, { section: title, count: 200 }),
        "the error identifies the new, numbered section"
      );
      assert.strictEqual(
        editor.sections.length,
        1,
        "refusing the add creates no section"
      );
    });

    test("a new destination is hidden at the section limit", async function (assert) {
      stubUnindexedTopics(2);
      const data = Array.from({ length: 50 }, (_, index) => ({
        id: index + 1,
        text: `Section ${index}`,
        links: [],
      }));
      const modal = this.owner.lookup("service:modal");
      const show = sinon.stub(modal, "show");
      const editor = await renderTopicEditor(data);
      editor.reviewUnindexedTopics();
      assert.false(
        show.firstCall.args[1].model.destinations.some(
          (option) => option.value === "new"
        ),
        "the destination picker respects the server's section limit"
      );
    });

    test("undo keeps a created section that gained other links", async function (assert) {
      stubUnindexedTopics(2);
      const editor = await renderTopicEditor([]);

      editor.addUnindexedTopics({ topics: [topic(7)], destination: "new" });
      editor.sections[0].links.push({
        title: "Manual",
        href: "/manual",
        type: "manual",
      });
      await settled();

      editor.undoLastAddition();
      await settled();

      assert.strictEqual(editor.sections.length, 1, "the section stays");
      assert.deepEqual(
        editor.sections[0].links.map((link) => link.title),
        ["Manual"],
        "holding only what was put there by hand"
      );
    });

    test("refuses to overfill a section", async function (assert) {
      stubUnindexedTopics(2);
      const links = Array.from({ length: 199 }, (_, i) => ({
        text: `Link ${i}`,
        href: `/l/${i}`,
      }));
      const editor = await renderTopicEditor([{ id: 10, text: "Full", links }]);

      const result = editor.addUnindexedTopics({
        topics: [topic(7), topic(8)],
        destination: "10",
      });

      assert.strictEqual(
        result.error,
        i18n(`${UNINDEXED}.section_room`, { section: "Full", count: 1 })
      );
      assert.strictEqual(
        editor.sections[0].links.length,
        199,
        "nothing is added"
      );
    });

    test("Apply ends the chance to undo", async function (assert) {
      stubUnindexedTopics(2);
      pretender.put("/doc-categories/indexes/1", () =>
        response({ index_structure: topicIndexData() })
      );
      const editor = await renderTopicEditor();

      editor.addUnindexedTopics({ topics: [topic(7)], destination: "10" });
      await settled();
      await editor.apply();
      await settled();

      assert.strictEqual(editor.lastAddition, null);
      assert.dom(".doc-category-index-editor__added-topics").doesNotExist();
    });
  }
);
