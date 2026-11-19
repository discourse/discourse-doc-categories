import { hash } from "@ember/helper";
import { render, settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import pretender, { response } from "discourse/tests/helpers/create-pretender";
import selectKit from "discourse/tests/helpers/select-kit-helper";
import { i18n } from "discourse-i18n";
import DocCategoryTopicChooser from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-topic-chooser";

module(
  "Integration | Component | Doc category topic chooser",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.site.updateCategory({
        id: 900,
        name: "Docs",
        slug: "docs",
        read_restricted: false,
      });
      this.site.updateCategory({
        id: 901,
        name: "Public",
        slug: "public",
        parent_category_id: 900,
        read_restricted: false,
      });
      this.site.updateCategory({
        id: 902,
        name: "Private",
        slug: "private",
        parent_category_id: 900,
        read_restricted: true,
      });
      this.selected = null;
      this.onChange = (id) => (this.selected = id);
    });

    for (const query of [
      "guide",
      "102",
      "http://localhost/t/private-guide/102",
    ]) {
      test(`excludes private cross-category results for ${query}`, async function (assert) {
        pretender.get("/search/query", () =>
          response({
            posts: [
              { id: 1, topic_id: 101 },
              { id: 2, topic_id: 102 },
            ],
            topics: [
              {
                id: 101,
                title: "Public guide",
                fancy_title: "Public guide",
                slug: "public-guide",
                category_id: 901,
              },
              {
                id: 102,
                title: "Private guide",
                fancy_title: "Private guide",
                slug: "private-guide",
                category_id: 902,
              },
            ],
          })
        );

        await render(
          <template>
            <DocCategoryTopicChooser
              @onChange={{this.onChange}}
              @options={{hash
                additionalFilters="in:title category:=900"
                docCategoryId=900
              }}
              @value={{null}}
            />
          </template>
        );
        const chooser = selectKit();
        await chooser.expand();
        await chooser.fillInFilter(query);

        assert.false(chooser.rowByValue(102).exists());
        assert.true(chooser.rowByValue(101).exists());
        await chooser.selectRowByValue(101);
        assert.strictEqual(this.selected, 101);
      });
    }

    test("allows a private category's own topics", async function (assert) {
      pretender.get("/search/query", () =>
        response({
          posts: [{ id: 2, topic_id: 102 }],
          topics: [
            {
              id: 102,
              title: "Private guide",
              fancy_title: "Private guide",
              slug: "private-guide",
              category_id: 902,
            },
          ],
        })
      );

      await render(
        <template>
          <DocCategoryTopicChooser
            @onChange={{this.onChange}}
            @options={{hash
              additionalFilters="in:title category:=902"
              docCategoryId=902
            }}
            @value={{null}}
          />
        </template>
      );
      const chooser = selectKit();
      await chooser.expand();
      await chooser.fillInFilter("guide");
      assert.true(chooser.rowByValue(102).exists());
      await chooser.selectRowByValue(102);
      assert.strictEqual(this.selected, 102);
    });

    test("rejects a topic when its category becomes private after searching", async function (assert) {
      pretender.get("/search/query", () =>
        response({
          posts: [{ id: 1, topic_id: 101 }],
          topics: [
            {
              id: 101,
              title: "Public guide",
              fancy_title: "Public guide",
              slug: "public-guide",
              category_id: 901,
            },
          ],
        })
      );
      await render(
        <template>
          <DocCategoryTopicChooser
            @onChange={{this.onChange}}
            @options={{hash
              additionalFilters="in:title category:=900"
              docCategoryId=900
            }}
            @value={{null}}
          />
        </template>
      );
      const chooser = selectKit();
      await chooser.expand();
      await chooser.fillInFilter("guide");
      assert.true(chooser.rowByValue(101).exists());

      this.site.updateCategory({ id: 901, read_restricted: true });
      await settled();
      await chooser.selectRowByValue(101);

      assert.strictEqual(this.selected, null);
      assert
        .dom(".select-kit-error")
        .hasText(
          i18n(
            "doc_categories.category_settings.sidebar_structure_editor.private_topics_help"
          )
        );
    });
  }
);
