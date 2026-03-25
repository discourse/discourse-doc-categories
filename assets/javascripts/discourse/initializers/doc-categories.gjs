import { withPluginApi } from "discourse/lib/plugin-api";
import DocCategorySettings from "../components/doc-category-settings";
import DocSimpleModeToggle from "../components/doc-simple-mode-toggle";
import DocUpdatedHeaderCell from "../components/doc-updated-header-cell";
import DocCategorySidebarPanel from "../lib/doc-category-sidebar-panel";
import isDocCategory, { DOC_ORIGINAL_STREAM } from "../lib/simple-mode";

export default {
  name: "doc-categories",
  initialize(container) {
    container.lookup("service:doc-category-sidebar");
    const siteSettings = container.lookup("service:site-settings");

    withPluginApi((api) => {
      api.registerCategorySaveProperty("doc_index_topic_id");
      api.registerCategorySaveProperty("doc_index_sections");
      if (!siteSettings.enable_simplified_category_creation) {
        // Legacy category edit flow uses the outlet; the new flow uses a registered tab.
        api.renderInOutlet("category-custom-settings", DocCategorySettings);
      }
      api.addSidebarPanel(DocCategorySidebarPanel);

      api.registerBehaviorTransformer(
        "post-stream-update-from-json",
        ({ next, context }) => {
          next();

          if (!siteSettings.doc_categories_simple_mode) {
            return;
          }

          const { postStream } = context;
          if (!isDocCategory(postStream.topic?.category)) {
            return;
          }

          postStream[DOC_ORIGINAL_STREAM] = [...postStream.stream];

          // When the user navigated directly to a reply URL (e.g., /t/slug/id/4),
          // keep all posts so they see the full thread.
          const enteredOnReply =
            postStream.loadingNearPost != null &&
            postStream.loadingNearPost > 1;
          if (!enteredOnReply && postStream.stream.length > 0) {
            postStream.stream.length = 1;
            const op = postStream.posts.find((p) => p.post_number === 1);
            postStream.posts.length = 0;
            if (op) {
              postStream.posts.push(op);
            }
          }
        }
      );

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
          if (!isDocCategory(context.category)) {
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

      api.renderAfterWrapperOutlet("post-links", DocSimpleModeToggle);
    });
  },
};
