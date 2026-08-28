import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import DocCategoryIndexTab from "discourse/plugins/discourse-doc-categories/discourse/components/doc-category-index-tab";

export default {
  name: "doc-categories-edit-tab",

  initialize() {
    withPluginApi((api) => {
      api.registerEditCategoryTab({
        id: "doc-index",
        name: i18n("doc_categories.category_settings.tab_title"),
        component: DocCategoryIndexTab,
        condition: ({ category, siteSettings }) =>
          siteSettings.doc_categories_enabled && !!category.id,
      });
    });
  },
};
