import { withPluginApi } from "discourse/lib/plugin-api";
import DocCategorySettings from "../components/doc-category-settings";
import DocCategorySidebarPanel from "../lib/doc-category-sidebar-panel";

export default {
  name: "doc-categories",
  initialize(container) {
    container.lookup("service:doc-category-sidebar");

    withPluginApi((api) => {
      api.registerCategorySaveProperty("doc_index_topic_id");
      api.renderInOutlet("category-custom-settings", DocCategorySettings);
      api.addSidebarPanel(DocCategorySidebarPanel);
    });
  },
};
