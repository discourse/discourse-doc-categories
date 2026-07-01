import { trackedArray } from "@ember/reactive/collections";
import { click, render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import DocSimpleModeToggle from "discourse/plugins/discourse-doc-categories/discourse/components/doc-simple-mode-toggle";
import {
  attachNewPostInterceptor,
  collapseStream,
  getState,
} from "discourse/plugins/discourse-doc-categories/discourse/lib/simple-mode";

function buildMockPostStream() {
  const opPost = { id: 100, post_number: 1 };
  const allPosts = [
    opPost,
    { id: 101, post_number: 2 },
    { id: 102, post_number: 3 },
    { id: 103, post_number: 4 },
  ];

  const postStream = {
    posts: trackedArray(allPosts.slice()),
    stream: trackedArray(allPosts.map((p) => p.id)),
    hasNoFilters: true,
    findLoadedPost(id) {
      return allPosts.find((p) => p.id === id) ?? null;
    },
    triggerNewPostsInStream(ids) {
      // Naive mock matching Core's "no filters" path: push missing IDs.
      for (const id of ids) {
        if (!this.stream.includes(id)) {
          this.stream.push(id);
        }
      }
    },
  };

  return postStream;
}

module("Integration | Component | doc-simple-mode-toggle", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.doc_categories_simple_mode = true;

    this.docTopic = {
      id: 50,
      replyCount: 3,
      category: { doc_index_topic_id: 54 },
      postStream: buildMockPostStream(),
    };

    // Mimic what the post-stream-update-from-json transformer does on first
    // load: attach the interceptor and collapse to the OP.
    attachNewPostInterceptor(this.docTopic.postStream);
    collapseStream(this.docTopic.postStream);
  });

  test("it only renders for the first post", async function (assert) {
    const outletArgs = {
      post: { post_number: 2, topic: this.docTopic },
    };

    await render(
      <template><DocSimpleModeToggle @outletArgs={{outletArgs}} /></template>
    );

    assert.dom(".doc-simple-mode-toggle__button").doesNotExist();
  });

  test("it does not render the toggle when the topic has no replies", async function (assert) {
    // Build a fresh topic with no replies (only the OP).
    const opPost = { id: 200, post_number: 1 };
    const topic = {
      id: 51,
      replyCount: 0,
      category: { doc_index_topic_id: 54 },
      postStream: {
        posts: trackedArray([opPost]),
        stream: trackedArray([opPost.id]),
        hasNoFilters: true,
        findLoadedPost: (id) => (id === opPost.id ? opPost : null),
        triggerNewPostsInStream() {},
      },
    };
    attachNewPostInterceptor(topic.postStream);
    collapseStream(topic.postStream);

    const outletArgs = { post: { post_number: 1, topic } };

    await render(
      <template><DocSimpleModeToggle @outletArgs={{outletArgs}} /></template>
    );

    assert.dom(".doc-simple-mode-toggle").doesNotExist();
  });

  test("it shows 'Hide comments' when stream is already expanded (e.g. after cloaking recreation)", async function (assert) {
    // Simulate a state where the user had previously expanded the comments.
    getState(this.docTopic.postStream).expanded = true;
    // Mirror the stream/posts state that an expanded postStream would have.
    this.docTopic.postStream.stream = trackedArray([100, 101, 102, 103]);

    const outletArgs = {
      post: { post_number: 1, topic: this.docTopic },
    };

    await render(
      <template><DocSimpleModeToggle @outletArgs={{outletArgs}} /></template>
    );

    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");
  });

  test("it toggles comments visibility across repeated clicks", async function (assert) {
    const { postStream } = this.docTopic;
    const outletArgs = {
      post: { post_number: 1, topic: this.docTopic },
    };

    await render(
      <template><DocSimpleModeToggle @outletArgs={{outletArgs}} /></template>
    );

    assert.dom(".doc-simple-mode-toggle__button").hasText("Show 3 comments");
    assert.deepEqual([...postStream.stream], [100]);
    assert.deepEqual(
      postStream.posts.map((p) => p.id),
      [100]
    );

    await click(".doc-simple-mode-toggle__button");
    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");
    assert.deepEqual(
      [...postStream.stream],
      [100, 101, 102, 103],
      "stream is restored to the original"
    );
    assert.deepEqual(
      postStream.posts.map((p) => p.id),
      [100, 101, 102, 103],
      "posts are restored from the identity map"
    );

    await click(".doc-simple-mode-toggle__button");
    assert.dom(".doc-simple-mode-toggle__button").hasText("Show 3 comments");
    assert.deepEqual(
      [...postStream.stream],
      [100],
      "stream is truncated to OP only"
    );
    assert.strictEqual(postStream.posts.length, 1, "posts retains only the OP");

    await click(".doc-simple-mode-toggle__button");
    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");
    assert.deepEqual(
      [...postStream.stream],
      [100, 101, 102, 103],
      "stream is restored again"
    );
  });

  test("MessageBus arrivals while collapsed increment the toggle count without revealing the new post", async function (assert) {
    const { postStream } = this.docTopic;
    const outletArgs = {
      post: { post_number: 1, topic: this.docTopic },
    };

    await render(
      <template><DocSimpleModeToggle @outletArgs={{outletArgs}} /></template>
    );

    assert.dom(".doc-simple-mode-toggle__button").hasText("Show 3 comments");

    await postStream.triggerNewPostsInStream([104]);
    await settled();

    assert
      .dom(".doc-simple-mode-toggle__button")
      .hasText(
        "Show 4 comments",
        "the new MessageBus arrival is counted in the toggle"
      );
    assert.deepEqual(
      [...postStream.stream],
      [100],
      "the new post is hidden away from the stream"
    );
    assert.true(
      getState(postStream).hiddenIds.includes(104),
      "the new post id is stashed in hiddenIds"
    );

    await click(".doc-simple-mode-toggle__button");
    assert.deepEqual(
      [...postStream.stream],
      [100, 101, 102, 103, 104],
      "expanding restores the original IDs plus the live arrival"
    );
  });
});
