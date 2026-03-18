import { click, render } from "@ember/test-helpers";
import { hbs } from "ember-cli-htmlbars";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";

module("Integration | Component | doc-simple-mode-toggle", function (hooks) {
  setupRenderingTest(hooks);

  hooks.beforeEach(function () {
    this.siteSettings.doc_categories_simple_mode = true;

    this.docTopic = {
      id: 50,
      replyCount: 3,
      category: { doc_index_topic_id: 54 },
      postStream: {
        posts: [],
        appendMore() {},
        canAppendMore: false,
      },
    };

    this.docSimpleModeState = this.owner.lookup(
      "service:doc-simple-mode-state"
    );
  });

  hooks.afterEach(function () {
    this.docSimpleModeState.reset();
  });

  test("it only renders for the first post", async function (assert) {
    this.outletArgs = {
      post: {
        post_number: 2,
        topic: this.docTopic,
      },
    };

    await render(hbs`<DocSimpleModeToggle @outletArgs={{this.outletArgs}} />`);

    assert.dom(".doc-simple-mode-toggle__button").doesNotExist();
  });

  test("it toggles comments visibility across repeated clicks", async function (assert) {
    this.outletArgs = {
      post: {
        post_number: 1,
        topic: this.docTopic,
      },
    };

    await render(hbs`<DocSimpleModeToggle @outletArgs={{this.outletArgs}} />`);

    assert.dom(".doc-simple-mode-toggle__button").hasText("Show 3 comments");

    await click(".doc-simple-mode-toggle__button");
    assert.true(
      document.body.classList.contains("doc-simple-mode--comments-visible")
    );
    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");

    await click(".doc-simple-mode-toggle__button");
    assert.false(
      document.body.classList.contains("doc-simple-mode--comments-visible")
    );
    assert.dom(".doc-simple-mode-toggle__button").hasText("Show 3 comments");

    await click(".doc-simple-mode-toggle__button");
    assert.true(
      document.body.classList.contains("doc-simple-mode--comments-visible")
    );
    assert.dom(".doc-simple-mode-toggle__button").hasText("Hide comments");
  });
});
