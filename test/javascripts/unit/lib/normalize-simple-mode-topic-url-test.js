import { module, test } from "qunit";
import normalizeSimpleModeTopicUrl from "discourse/plugins/discourse-doc-categories/discourse/lib/normalize-simple-mode-topic-url";

module("Unit | Utility | normalize-simple-mode-topic-url", function (hooks) {
  hooks.afterEach(function () {
    window.history.pushState({}, "", "/");
  });

  test("it does nothing when already on the topic root", async function (assert) {
    window.history.pushState({}, "", "/t/topic/123?nocache=1");

    normalizeSimpleModeTopicUrl("/t/topic/123");

    assert.strictEqual(
      `${window.location.pathname}${window.location.search}`,
      "/t/topic/123?nocache=1"
    );
  });

  test("it normalizes reply routes back to the topic root", async function (assert) {
    window.history.pushState({}, "", "/t/topic/123/4?nocache=1");

    normalizeSimpleModeTopicUrl("/t/topic/123");

    assert.strictEqual(
      `${window.location.pathname}${window.location.search}`,
      "/t/topic/123?nocache=1"
    );
  });
});
