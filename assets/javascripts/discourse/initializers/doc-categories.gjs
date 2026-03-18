import { withPluginApi } from "discourse/lib/plugin-api";
import DocCategorySettings from "../components/doc-category-settings";
import DocCategorySettingsForm from "../components/doc-category-settings-form";
import DocSimpleModeToggle from "../components/doc-simple-mode-toggle";
import DocSimpleModeTopic from "../components/doc-simple-mode-topic";
import DocUpdatedHeaderCell from "../components/doc-updated-header-cell";
import DocCategorySidebarPanel from "../lib/doc-category-sidebar-panel";
import isDocCategory from "../lib/is-doc-category";

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

      api.registerValueTransformer(
        "topic-list-columns",
        ({ value: columns, context }) => {
          if (!siteSettings.doc_categories_simple_mode) {
            return columns;
          }
          if (!isDocCategory(context.category)) {
            return columns;
          }
          columns.delete("posters");
          columns.delete("replies");
          columns.replace("activity", { header: DocUpdatedHeaderCell });
          return columns;
        }
      );

      api.registerValueTransformer(
        "topic-list-class",
        ({ value: classes, context }) => {
          if (!siteSettings.doc_categories_simple_mode) {
            return classes;
          }
          const category = context.topics?.[0]?.category;
          if (!isDocCategory(category)) {
            return classes;
          }
          classes.push("doc-simple-mode");
          return classes;
        }
      );

      api.registerValueTransformer(
        "more-topics-tabs",
        ({ value: tabs, context }) => {
          if (!siteSettings.doc_categories_simple_mode) {
            return tabs;
          }
          if (!isDocCategory(context.topic?.category)) {
            return tabs;
          }
          return tabs.filter((tab) => tab.id !== "suggested-topics");
        }
      );

      api.renderInOutlet("topic-above-post-stream", DocSimpleModeTopic);
      api.renderAfterWrapperOutlet("post-links", DocSimpleModeToggle);
    });
  },
};
