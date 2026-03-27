import { click, render } from "@ember/test-helpers";
import { TrackedArray } from "@ember-compat/tracked-built-ins";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import DocSimpleModeToggle from "discourse/plugins/discourse-doc-categories/discourse/components/doc-simple-mode-toggle";
import { DOC_ORIGINAL_STREAM } from "discourse/plugins/discourse-doc-categories/discourse/lib/simple-mode";

module("Integration | Component | doc-simple-mode-toggle", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.doc_categories_simple_mode = true;

    this.docTopic = {
      id: 50,
      replyCount: 3,
      category: { doc_index_topic_id: 54 },
      postStream: {
        posts: new TrackedArray([]),
        stream: new TrackedArray([]),
        findLoadedPost(id) {
          if (id === 100) {
            return { post_number: 1 };
          }
          return null;
        },
        [DOC_ORIGINAL_STREAM]: [100, 101, 102, 103],
      },
    };
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

  test("it shows 'Hide comments' when stream is already expanded (e.g. after cloaking recreation)", async function (assert) {
    // Simulate a state where comments were expanded before component was destroyed
    // by cloaking: stream has all post IDs (not just the OP)
    this.docTopic.postStream.stream = new TrackedArray([100, 101, 102, 103]);

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
    assert.deepEqual([...postStream.stream], []);
    assert.deepEqual([...postStream.posts], []);

    await click(".doc-simple-mode-toggle__button");
    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");
    assert.deepEqual(
      [...postStream.stream],
      [100, 101, 102, 103],
      "stream is restored to the original"
    );
    assert.deepEqual(
      postStream.posts.length,
      1,
      "only the OP is added to posts (other posts are lazy-loaded)"
    );

    await click(".doc-simple-mode-toggle__button");
    assert.dom(".doc-simple-mode-toggle__button").hasText("Show 3 comments");
    assert.deepEqual(
      [...postStream.stream],
      [100],
      "stream is truncated to OP only"
    );
    assert.deepEqual(postStream.posts.length, 1, "posts retains only the OP");

    await click(".doc-simple-mode-toggle__button");
    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");
    assert.deepEqual(
      [...postStream.stream],
      [100, 101, 102, 103],
      "stream is restored again"
    );
  });
});
