import { settled, waitUntil } from "@ember/test-helpers";
import { setupTest } from "ember-qunit";
import { module, test } from "qunit";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import {
  draftTopicIds,
  draftTopicReferences,
  topicIdFromHref,
  UnindexedTopicsCounter,
} from "discourse/plugins/discourse-doc-categories/discourse/lib/doc-index-unindexed-topics";

function sections(...links) {
  return [{ title: "Only", links }];
}

module("Unit | Lib | doc-index-unindexed-topics", function (hooks) {
  setupTest(hooks);

  test("topicIdFromHref reads same-site topic URLs only", function (assert) {
    assert.strictEqual(topicIdFromHref("/t/some-topic/12"), 12);
    assert.strictEqual(topicIdFromHref("/t/some-topic/12/3"), 12, "post");
    assert.strictEqual(topicIdFromHref("/t/12"), 12, "slugless");
    assert.strictEqual(
      topicIdFromHref(`${window.location.origin}/t/some-topic/12`),
      12,
      "absolute on this site"
    );
    assert.strictEqual(
      topicIdFromHref("https://example.com/t/some-topic/12"),
      null,
      "another site's topic is not ours"
    );
    assert.strictEqual(topicIdFromHref("/c/docs/4"), null);
    assert.strictEqual(topicIdFromHref(""), null);
  });

  test("draftTopicReferences sorts, dedupes and leaves unsettled links out", function (assert) {
    const references = draftTopicReferences(
      sections(
        { href: "/t/b/9", topic_id: 9 },
        { href: "/t/a/3", topic_id: 3 },
        { href: "/t/a/3", topic_id: 3 },
        { href: "/t/manual/4" },
        { href: "https://example.com" },
        { href: "/half-typed", isEditing: true },
        { href: " " }
      )
    );

    assert.deepEqual(references, {
      topicIds: [3, 9],
      hrefs: ["/t/manual/4"],
    });
  });

  test("external URLs never affect exclusions, including overlong and lookalike-host URLs", function (assert) {
    const hostname = window.location.hostname;
    const references = draftTopicReferences(
      sections(
        { href: `https://example.com/${"x".repeat(2500)}` },
        { href: `https://${hostname}.example.com/t/manual/4` }
      )
    );

    assert.deepEqual(
      references,
      { topicIds: [], hrefs: [] },
      "only this site's references are sent"
    );
    assert.strictEqual(
      topicIdFromHref(`https://${hostname}.example.com/t/manual/4`),
      null,
      "a hostname prefix is not the same site"
    );
  });

  test("URL-only references match Apply's character limit before server resolution", function (assert) {
    const href = `/t/manual/4?tracking=${"x".repeat(2500)}`;
    const unicodeHref = `/t/manual/5?tracking=${"😀".repeat(2000)}`;
    const references = draftTopicReferences(
      sections({ href }, { href: unicodeHref })
    );

    assert.deepEqual(
      references.hrefs,
      [href.slice(0, 2000), [...unicodeHref].slice(0, 2000).join("")],
      "hrefs use the same 2000-character prefix as Apply"
    );
    assert.strictEqual(
      topicIdFromHref(href),
      4,
      "long query strings do not prevent recognizing a topic"
    );
  });

  test("draftTopicIds resolves topic URLs on links without an id", function (assert) {
    const ids = draftTopicIds(
      sections({ href: "/t/a/3", topic_id: 3 }, { href: "/t/manual/4" })
    );

    assert.deepEqual([...ids].sort(), [3, 4]);
  });

  test("the counter only asks again when the references or scope change", async function (assert) {
    const requests = [];
    pretender.post("/doc-categories/indexes/1/unindexed_topics", (request) => {
      requests.push(JSON.parse(request.requestBody));
      return response({ topics: [], total_count: requests.length });
    });
    const counter = new UnindexedTopicsCounter(1);
    const query = {
      references: { topicIds: [1], hrefs: [] },
      includeSubcategories: false,
    };

    counter.update(query, { immediate: true });
    await settled();
    assert.strictEqual(counter.count, 1);
    assert.strictEqual(requests[0].limit, 0, "it asks for a count only");

    counter.update({ ...query, references: { topicIds: [1], hrefs: [] } });
    await settled();
    assert.strictEqual(requests.length, 1, "equal references are not news");

    counter.update({ ...query, includeSubcategories: true });
    await settled();
    assert.strictEqual(requests.length, 2, "a wider scope is");
    assert.strictEqual(counter.count, 2);

    counter.update({ ...query, includeSubcategories: true }, { force: true });
    await settled();
    assert.strictEqual(requests.length, 3, "and force asks regardless");

    counter.teardown();
  });

  test("the counter hides failed counts and retries unchanged references", async function (assert) {
    let requests = 0;
    pretender.post("/doc-categories/indexes/1/unindexed_topics", () => {
      requests++;
      return requests === 1
        ? response(500, { errors: ["Unavailable"] })
        : response({ topics: [], total_count: 3 });
    });
    const counter = new UnindexedTopicsCounter(1);
    const query = {
      references: { topicIds: [], hrefs: [] },
      includeSubcategories: false,
    };
    counter.update(query, { immediate: true });
    await settled();
    assert.strictEqual(
      counter.count,
      null,
      "a failed lookup leaves the count unknown"
    );
    assert.false(counter.isLoading, "a failure finishes loading");
    counter.update(query, { immediate: true });
    await settled();
    assert.strictEqual(
      requests,
      2,
      "unchanged references can be retried after failure"
    );
    assert.strictEqual(
      counter.count,
      3,
      "the retry restores the advisory count"
    );
    counter.teardown();
  });

  test("the counter keeps only the newest answer when the older request finishes last", async function (assert) {
    const counter = new UnindexedTopicsCounter(1);
    const resolveRequests = [];
    pretender.post(
      "/doc-categories/indexes/1/unindexed_topics",
      () =>
        new Promise((resolveRequest) => resolveRequests.push(resolveRequest))
    );
    counter.update(
      { references: { topicIds: [], hrefs: [] }, includeSubcategories: false },
      { immediate: true }
    );
    counter.update(
      { references: { topicIds: [], hrefs: [] }, includeSubcategories: true },
      { immediate: true }
    );
    await waitUntil(() => resolveRequests.length === 2);
    resolveRequests[1](response({ topics: [], total_count: 9 }));
    await waitUntil(() => counter.count === 9);
    assert.false(
      counter.isLoading,
      "the latest response finishes loading before the older one"
    );
    resolveRequests[0](response({ topics: [], total_count: 1 }));
    await settled();
    assert.strictEqual(counter.count, 9, "the late older answer is discarded");
    counter.teardown();
  });
});
