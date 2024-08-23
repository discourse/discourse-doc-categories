import { withPluginApi } from "discourse/lib/plugin-api";
import I18n from "discourse-i18n";
import DocCategorySettings from "../components/doc-category-settings";
import DocCategorySidebarPanel from "../lib/doc-category-sidebar-panel";

export default {
  name: "doc-categories",
  initialize(container) {
    container.lookup("service:doc-category-sidebar");

    withPluginApi("1.34.0", (api) => {
      api.renderInOutlet("category-custom-settings", DocCategorySettings);
      api.addSidebarPanel(DocCategorySidebarPanel);
      api.addAdvancedSearchOptions({
        inOptionsForAll: [
          {
            name: I18n.t("doc_categories.search.advanced.in.docs"),
            value: "docs",
            special: true,
          },
        ],
      });
    });
  },
};
