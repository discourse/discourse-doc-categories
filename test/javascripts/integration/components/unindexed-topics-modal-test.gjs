import { click, find, render, settled, waitUntil } from "@ember/test-helpers";
import { module, test } from "qunit";
import sinon from "sinon";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import formKit from "discourse/tests/helpers/form-kit-helper";
import { i18n } from "discourse-i18n";
import UnindexedTopicsModal from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-index-editor/unindexed-topics-modal";

const PREFIX = "doc_categories.category_settings.index_editor.unindexed_topics";

function topic(id, categoryId = 1) {
  return {
    id,
    title: `Topic ${id}`,
    slug: `topic-${id}`,
    category_id: categoryId,
  };
}

/**
 * Serves `total` candidates fifty to a page and records each request body.
 * `answer` may override a reply with a payload, an error status, or a delay.
 */
function stubCandidates(total, answer = () => null) {
  const requests = [];
  pretender.post(
    "/doc-categories/indexes/1/unindexed_topics",
    async (request) => {
      const body = JSON.parse(request.requestBody);
      requests.push(body);

      const reply = answer(body);
      if (reply?.delay) {
        await new Promise((resolve) => setTimeout(resolve, reply.delay));
      }
      if (reply?.status) {
        return response(reply.status, { errors: ["Nope"] });
      }
      if (reply?.payload) {
        return response({ page: body.page, per_page: 50, ...reply.payload });
      }

      const first = body.page * 50 + 1;
      const last = Math.min(total, first + 49);
      const topics = [];
      for (let id = first; id <= last; id++) {
        topics.push(topic(100 + id));
      }
      return response({
        topics,
        total_count: total,
        page: body.page,
        per_page: 50,
      });
    }
  );
  return requests;
}

/** Types without waiting, so two edits can land inside one debounce window. */
function typeInto(input, text) {
  input.value = text;
  input.dispatchEvent(new Event("input", { bubbles: true }));
}

function buildModel(overrides = {}) {
  return {
    categoryId: 1,
    destinations: [
      { value: "10", label: "Start here", linkCount: 1 },
      { value: "11", label: "Reference", linkCount: 2 },
    ],
    initialDestination: "11",
    includeSubcategories: false,
    canIncludeSubcategories: true,
    getReferences: () => ({ topicIds: [1, 2], hrefs: ["/t/guide/5"] }),
    addTopics: sinon.stub().returns({ added: 1 }),
    ...overrides,
  };
}

async function renderModal(model, closeModal = () => {}) {
  await render(
    <template>
      <UnindexedTopicsModal
        @closeModal={{closeModal}}
        @inline={{true}}
        @model={{model}}
      />
    </template>
  );
}

module("Integration | Component | UnindexedTopicsModal", function (hooks) {
  setupRenderingTest(hooks);

  test("asks for the candidates the draft leaves out", async function (assert) {
    const requests = stubCandidates(2);
    await renderModal(buildModel());

    assert.deepEqual(
      requests[0],
      {
        exclude_topic_ids: [1, 2],
        exclude_hrefs: ["/t/guide/5"],
        include_subcategories: false,
        page: 0,
      },
      "it sends the draft's references in the picker's starting scope"
    );
    assert
      .dom(".doc-category-unindexed-topics [data-topic-id]")
      .exists({ count: 2 }, "and lists each candidate");
    assert
      .dom(".doc-category-unindexed-topics__add")
      .isDisabled("nothing can be added before something is chosen");
  });

  test("adds the chosen topics to the chosen section", async function (assert) {
    stubCandidates(2);
    const model = buildModel();
    const closeModal = sinon.spy();
    await renderModal(model, closeModal);

    assert.strictEqual(
      formKit().field("section_id").value(),
      "11",
      "the destination starts where the editor pointed it"
    );

    await formKit().field("topic_102").toggle();
    await formKit().field("section_id").select("10");

    assert
      .dom(".doc-category-unindexed-topics__add")
      .hasText(i18n(`${PREFIX}.add`, { count: 1 }), "the button counts them");

    await click(".doc-category-unindexed-topics__add");

    assert.true(model.addTopics.calledOnce, "it commits once");
    assert.deepEqual(
      model.addTopics.firstCall.args[0],
      { topics: [topic(102)], destination: "10" },
      "with the chosen topic and section"
    );
    assert.true(closeModal.calledOnce, "and closes");
  });

  test("keeps the modal open when the commit is refused", async function (assert) {
    stubCandidates(1);
    const model = buildModel({
      addTopics: sinon.stub().returns({ error: "No room" }),
    });
    const closeModal = sinon.spy();
    await renderModal(model, closeModal);

    await formKit().field("topic_101").toggle();
    await click(".doc-category-unindexed-topics__add");

    assert.false(closeModal.called, "it stays open");
    assert
      .dom(".doc-category-unindexed-topics .alert-error")
      .hasText("No room", "and says why");
  });

  test("choices survive loading more", async function (assert) {
    const requests = stubCandidates(60);
    await renderModal(buildModel());

    await formKit().field("topic_101").toggle();
    await click(".doc-category-unindexed-topics__load-more");

    assert.strictEqual(requests.at(-1).page, 1, "it asks for the next page");
    assert
      .dom(".doc-category-unindexed-topics [data-topic-id]")
      .exists({ count: 60 }, "and appends it");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .doesNotExist("with nothing left to load");
    assert.true(
      formKit().field("topic_101").value(),
      "the earlier choice still stands"
    );
  });

  test("selecting everything shown, then clearing", async function (assert) {
    stubCandidates(3);
    await renderModal(buildModel());

    await click(".doc-category-unindexed-topics__select-shown");
    assert
      .dom(".doc-category-unindexed-topics__add")
      .hasText(i18n(`${PREFIX}.add`, { count: 3 }));

    await click(".doc-category-unindexed-topics__clear-selection");
    assert
      .dom(".doc-category-unindexed-topics__add")
      .isDisabled("clearing leaves nothing to add");
    assert.false(formKit().field("topic_101").value());
  });

  test("changing the scope starts the choice over", async function (assert) {
    const requests = stubCandidates(2);
    await renderModal(buildModel());

    await formKit().field("topic_101").toggle();
    await formKit().field("include_subcategories").toggle();

    assert.true(
      requests.at(-1).include_subcategories,
      "it asks again with subcategories"
    );
    assert.strictEqual(requests.at(-1).page, 0, "from the first page");
    assert.false(
      formKit().field("topic_101").value(),
      "and the old scope's choice is dropped"
    );
    assert.dom(".doc-category-unindexed-topics__add").isDisabled();
  });

  test("offers subcategories only when there are some", async function (assert) {
    stubCandidates(1);
    await renderModal(buildModel({ canIncludeSubcategories: false }));

    assert.false(
      formKit().hasField("include_subcategories"),
      "a category without subcategories has no scope to widen"
    );
  });

  test("searching narrows the candidates without dropping choices", async function (assert) {
    const requests = stubCandidates(2);
    await renderModal(buildModel());

    await formKit().field("topic_101").toggle();
    await formKit().field("search").fillIn("guide");

    assert.strictEqual(requests.at(-1).search, "guide", "it searches titles");
    assert
      .dom(".doc-category-unindexed-topics__add")
      .hasText(
        i18n(`${PREFIX}.add`, { count: 1 }),
        "a choice made before searching still counts"
      );
  });

  test("a failed search drops the old results and retries from the first page", async function (assert) {
    let refuseSearch = true;
    const requests = stubCandidates(120, (body) =>
      refuseSearch && body.search ? { status: 500 } : null
    );
    await renderModal(buildModel());

    await click(".doc-category-unindexed-topics__load-more");
    await formKit().field("topic_101").toggle();
    await formKit().field("search").fillIn("guide");

    assert.strictEqual(
      requests.at(-1).search,
      "guide",
      "the search reaches the server"
    );
    assert
      .dom(".doc-category-unindexed-topics .alert-error")
      .hasText(
        i18n("generic_error_with_reason", { error: "Nope" }),
        "the failure is reported"
      );
    assert
      .dom("[data-topic-id]")
      .doesNotExist("the previous query's pages are gone");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .doesNotExist("so paging cannot skip the failed query");
    assert
      .dom(".doc-category-unindexed-topics__counts")
      .hasText(
        i18n(`${PREFIX}.selected`, { count: 1 }),
        "the choice made before the failure is still reachable"
      );

    refuseSearch = false;
    await click(".doc-category-unindexed-topics__retry");

    assert.deepEqual(
      { page: requests.at(-1).page, search: requests.at(-1).search },
      { page: 0, search: "guide" },
      "retrying starts the search over from its first page"
    );
    assert
      .dom("[data-topic-id]")
      .exists({ count: 50 }, "and lists only that page");
    assert.true(
      formKit().field("topic_101").value(),
      "the choice made before the failure still counts"
    );
    assert
      .dom(".doc-category-unindexed-topics .alert-error")
      .doesNotExist("the failure clears");
  });

  test("a search with no matches keeps the choice reachable", async function (assert) {
    stubCandidates(2, (body) =>
      body.search ? { payload: { topics: [], total_count: 0 } } : null
    );
    await renderModal(buildModel());

    await formKit().field("topic_101").toggle();
    await formKit().field("search").fillIn("missing");

    assert
      .dom(".doc-category-unindexed-topics [data-topic-id]")
      .doesNotExist("nothing matches");
    assert
      .dom(".doc-category-unindexed-topics__counts")
      .hasText(
        i18n(`${PREFIX}.selected`, { count: 1 }),
        "the choice is still counted"
      );
    assert
      .dom(".doc-category-unindexed-topics__add")
      .hasText(i18n(`${PREFIX}.add`, { count: 1 }), "and still addable");

    await click(".doc-category-unindexed-topics__clear-selection");
    assert
      .dom(".doc-category-unindexed-topics__add")
      .isDisabled("so it can still be cleared");
  });

  test("typing again replaces the pending search and ignores paging", async function (assert) {
    const requests = stubCandidates(120);
    await renderModal(buildModel());

    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .exists("more pages are on offer");

    const input = find("input[name='search']");
    typeInto(input, "gui");
    typeInto(input, "guide");

    find(".doc-category-unindexed-topics__load-more").click();
    await settled();

    assert.deepEqual(
      requests.map((request) => [request.page, request.search ?? null]),
      [
        [0, null],
        [0, "guide"],
      ],
      "the pending search wins: only the last text is asked for, from the first page"
    );
  });

  test("the search field keeps what was typed and can be cleared", async function (assert) {
    const requests = stubCandidates(2);
    await renderModal(buildModel());

    await formKit().field("search").fillIn("guide");
    assert.strictEqual(
      formKit().field("search").value(),
      "guide",
      "the field holds the search"
    );
    assert.strictEqual(requests.at(-1).search, "guide", "which was asked for");

    await formKit().field("search").fillIn("");
    assert.strictEqual(
      formKit().field("search").value(),
      "",
      "the field empties"
    );
    assert.strictEqual(
      requests.at(-1).search,
      undefined,
      "and the next query has no search"
    );
  });

  test("the search is capped at 200 characters", async function (assert) {
    const requests = stubCandidates(2);
    await renderModal(buildModel());

    const input = find("input[name='search']");
    assert
      .dom(input)
      .hasAttribute("maxlength", "200", "typing stops at the cap");

    input.value = "x".repeat(250);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    await settled();

    assert.strictEqual(input.value.length, 200, "and so does the value");
    assert.strictEqual(
      requests.at(-1).search.length,
      200,
      "as well as the search that is sent"
    );
  });

  test("a failed page keeps the results and retries that page", async function (assert) {
    let refusePage = true;
    const requests = stubCandidates(60, (body) =>
      refusePage && body.page === 1 ? { status: 500 } : null
    );
    await renderModal(buildModel());

    await click(".doc-category-unindexed-topics__load-more");

    assert
      .dom("[data-topic-id]")
      .exists({ count: 50 }, "the failed page adds nothing");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .doesNotExist("and cannot be skipped");
    assert
      .dom(".doc-category-unindexed-topics__retry")
      .exists("a retry is offered");

    refusePage = false;
    await click(".doc-category-unindexed-topics__retry");

    assert.strictEqual(requests.at(-1).page, 1, "it asks for the same page");
    assert
      .dom("[data-topic-id]")
      .exists({ count: 60 }, "which is then appended");
  });

  test("paging ends at the server's last page even if a page contains only duplicates", async function (assert) {
    stubCandidates(100, (body) =>
      body.page === 1
        ? {
            payload: {
              topics: Array.from({ length: 50 }, (_, index) =>
                topic(101 + index)
              ),
              total_count: 100,
            },
          }
        : null
    );
    await renderModal(buildModel());
    await click(".doc-category-unindexed-topics__load-more");

    assert
      .dom("[data-topic-id]")
      .exists({ count: 50 }, "duplicate rows are not repeated");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .doesNotExist(
        "server page position, not the unique row count, determines exhaustion"
      );
  });

  test("a duplicate page can advance to a later page that still has new topics", async function (assert) {
    stubCandidates(120, (body) =>
      body.page === 1
        ? {
            payload: {
              topics: Array.from({ length: 50 }, (_, index) =>
                topic(101 + index)
              ),
              total_count: 120,
            },
          }
        : null
    );
    await renderModal(buildModel());
    await click(".doc-category-unindexed-topics__load-more");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .exists("a duplicate page is not necessarily the end");
    await click(".doc-category-unindexed-topics__load-more");
    assert
      .dom("[data-topic-id]")
      .exists({ count: 70 }, "new rows on the next page are still reachable");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .doesNotExist("the server's last page then ends paging");
  });

  test("an empty page ends paging instead of leaving an endless Load more button", async function (assert) {
    stubCandidates(120, (body) =>
      body.page === 1 ? { payload: { topics: [], total_count: 120 } } : null
    );
    await renderModal(buildModel());
    await click(".doc-category-unindexed-topics__load-more");
    assert
      .dom("[data-topic-id]")
      .exists({ count: 50 }, "already loaded rows stay available");
    assert
      .dom(".doc-category-unindexed-topics__load-more")
      .doesNotExist("an empty page is a terminal response");
  });

  test("a page answering after the search starts cannot join it", async function (assert) {
    const requests = stubCandidates(120, (body) =>
      body.page === 1 ? { delay: 50 } : null
    );
    await renderModal(buildModel());

    const appendClick = click(".doc-category-unindexed-topics__load-more");
    await waitUntil(() => requests.length === 2);
    const searchFill = formKit().field("search").fillIn("guide");
    await appendClick;
    await searchFill;

    assert.deepEqual(
      requests.map((request) => [request.page, request.search ?? null]),
      [
        [0, null],
        [1, null],
        [0, "guide"],
      ],
      "the slow page answers after the search was requested"
    );
    assert
      .dom("[data-topic-id]")
      .exists({ count: 50 }, "so only the search's page is listed");
  });

  test("refuses more topics than the section has room for", async function (assert) {
    stubCandidates(3);
    await renderModal(
      buildModel({
        destinations: [{ value: "10", label: "Start here", linkCount: 199 }],
        initialDestination: "10",
      })
    );

    await formKit().field("topic_101").toggle();
    assert
      .dom(".doc-category-unindexed-topics__add")
      .isEnabled("one more fits");

    await formKit().field("topic_102").toggle();
    assert.dom(".doc-category-unindexed-topics__add").isDisabled("two do not");
    assert
      .dom(".doc-category-unindexed-topics__capacity")
      .hasText(
        i18n(`${PREFIX}.section_room`, { section: "Start here", count: 1 }),
        "and it says how many would"
      );
  });

  test("marks topics from other categories and links each to itself", async function (assert) {
    const subcategory = this.site.categories.find((c) => c.id !== 1);
    pretender.post("/doc-categories/indexes/1/unindexed_topics", () =>
      response({
        topics: [topic(7), topic(8, subcategory.id)],
        total_count: 2,
        page: 0,
        per_page: 50,
      })
    );
    await renderModal(buildModel());

    assert
      .dom("[data-topic-id='7'] .badge-category__wrapper")
      .doesNotExist("a topic of the indexed category needs no badge");
    assert
      .dom("[data-topic-id='8'] .badge-category__wrapper")
      .exists("one from elsewhere is marked");
    assert
      .dom("[data-topic-id='7'] .doc-category-unindexed-topics__topic-link")
      .hasAttribute("href", "/t/topic-7/7")
      .hasAttribute("target", "_blank")
      .hasAttribute(
        "aria-label",
        i18n(`${PREFIX}.open_topic`, { title: topic(7).title })
      );
  });
});
