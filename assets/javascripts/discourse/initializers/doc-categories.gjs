import { withPluginApi } from "discourse/lib/plugin-api";
import DocCategorySettings from "../components/doc-category-settings";
import DocCategorySettingsForm from "../components/doc-category-settings-form";
import DocCategorySidebarPanel from "../lib/doc-category-sidebar-panel";

export default {
  name: "doc-categories",
  initialize(container) {
    container.lookup("service:doc-category-sidebar");
    const siteSettings = container.lookup("service:site-settings");

    withPluginApi((api) => {
      api.registerCategorySaveProperty("doc_index_topic_id");
      if (siteSettings.enable_simplified_category_creation) {
        api.renderInOutlet("category-custom-settings", DocCategorySettingsForm);
      } else {
        api.renderInOutlet("category-custom-settings", DocCategorySettings);
      }
      api.addSidebarPanel(DocCategorySidebarPanel);
    });
  },
};
