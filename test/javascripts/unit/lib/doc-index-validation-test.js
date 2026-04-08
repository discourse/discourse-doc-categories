import { module, test } from "qunit";
import validateDocIndexSections from "discourse/plugins/discourse-doc-categories/discourse/lib/doc-index-validation";

module("Unit | Lib | doc-index-validation", function () {
  test("allows the first section to have an empty title", function (assert) {
    const sections = [
      { title: "", links: [{ title: "Link", href: "/a", type: "manual" }] },
    ];

    const errors = validateDocIndexSections(sections);
    assert.deepEqual(errors, []);
  });

  test("returns error for non-first sections with empty title", function (assert) {
    const sections = [
      {
        title: "First",
        links: [{ title: "Link", href: "/a", type: "manual" }],
      },
      { title: "", links: [{ title: "Link", href: "/b", type: "manual" }] },
    ];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });

  test("returns error for non-first sections with whitespace-only title", function (assert) {
    const sections = [
      {
        title: "First",
        links: [{ title: "Link", href: "/a", type: "manual" }],
      },
      { title: "   ", links: [{ title: "Link", href: "/b", type: "manual" }] },
    ];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });

  test("does not return title error for first section even with multiple sections", function (assert) {
    const sections = [
      { title: "", links: [{ title: "Link", href: "/a", type: "manual" }] },
      {
        title: "Second",
        links: [{ title: "Link", href: "/b", type: "manual" }],
      },
    ];

    const errors = validateDocIndexSections(sections);
    assert.deepEqual(errors, []);
  });
});
