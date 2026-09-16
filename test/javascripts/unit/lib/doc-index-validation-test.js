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

  test("returns error for sections with no links", function (assert) {
    const sections = [{ title: "Empty", links: [] }];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });

  test("does not return empty section error for autoIndex sections with no links", function (assert) {
    const sections = [{ title: "Auto", links: [], autoIndex: true }];

    const errors = validateDocIndexSections(sections);
    assert.deepEqual(errors, []);
  });

  test("returns error for links with empty title on non-topic type", function (assert) {
    const sections = [
      {
        title: "Section",
        links: [{ title: "", href: "/a", type: "manual" }],
      },
    ];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });

  test("does not return link title error for topic type links", function (assert) {
    const sections = [
      {
        title: "Section",
        links: [{ title: "", href: "/a", type: "topic" }],
      },
    ];

    const errors = validateDocIndexSections(sections);
    assert.deepEqual(errors, []);
  });

  test("returns error for links with empty href", function (assert) {
    const sections = [
      {
        title: "Section",
        links: [{ title: "Link", href: "", type: "manual" }],
      },
    ];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });

  test("returns error for links with whitespace-only href", function (assert) {
    const sections = [
      {
        title: "Section",
        links: [{ title: "Link", href: "   ", type: "manual" }],
      },
    ];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });

  test("deduplicates identical errors across multiple sections", function (assert) {
    const sections = [
      { title: "First", links: [] },
      { title: "Second", links: [] },
    ];

    const errors = validateDocIndexSections(sections);
    assert.strictEqual(errors.length, 1);
  });
});
