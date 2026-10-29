import { isPresent } from "@ember/utils";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import DocCategoryIndexTab from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-index-tab";

export default {
  name: "doc-categories-edit-tab",

  initialize(container) {
    // Register before FormKit's dirty guard: a pending save cannot be discarded.
    container.lookup("service:doc-index-save-lock");

    withPluginApi((api) => {
      api.registerEditCategoryTab({
        id: "doc-index",
        name: i18n("doc_categories.category_settings.tab_title"),
        component: DocCategoryIndexTab,
        primary: ({ category }) => !!category.doc_index_topic_id,
        condition: ({ category, siteSettings }) =>
          siteSettings.doc_categories_enabled && isPresent(category.id),
      });
    });
  },
};
