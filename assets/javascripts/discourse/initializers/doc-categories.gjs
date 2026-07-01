import { schedule } from "@ember/runloop";
import DiscourseURL from "discourse/lib/url";
import { withPluginApi } from "discourse/lib/plugin-api";
import DocCategorySettings from "../components/doc-category-settings";
import DocCategorySettingsForm from "../components/doc-category-settings-form";
import DocSimpleModeToggle from "../components/doc-simple-mode-toggle";
import DocUpdatedHeaderCell from "../components/doc-updated-header-cell";
import DocCategorySidebarPanel from "../lib/doc-category-sidebar-panel";
import {
  attachNewPostInterceptor,
  collapseStream,
  getState,
  inDocSimpleMode,
} from "../lib/simple-mode";

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

      api.registerBehaviorTransformer(
        "post-stream-update-from-json",
        ({ next, context }) => {
          next();

          const { postStream } = context;
          if (!inDocSimpleMode(siteSettings, postStream.topic?.category)) {
            return;
          }

          attachNewPostInterceptor(postStream);
          const state = getState(postStream);

          if (state.expanded === undefined) {
            // First load for this postStream. When the user navigated directly
            // to a reply URL (e.g., /t/slug/id/4), start expanded so they see
            // the full thread.
            const enteredOnReply =
              postStream.loadingNearPost != null &&
              postStream.loadingNearPost > 1;
            state.expanded = enteredOnReply;
          }

          if (!state.expanded) {
            collapseStream(postStream);
          }
        }
      );

      api.registerValueTransformer(
        "topic-list-columns",
        ({ value: columns, context }) => {
          if (!inDocSimpleMode(siteSettings, context.category)) {
            return columns;
          }
          columns.delete("posters");
          columns.delete("replies");
          columns.delete("views");
          columns.replace("activity", { header: DocUpdatedHeaderCell });
          return columns;
        }
      );

      api.registerValueTransformer(
        "topic-list-class",
        ({ value: classes, context }) => {
          if (!inDocSimpleMode(siteSettings, context.category)) {
            return classes;
          }
          classes.push("doc-simple-mode");
          return classes;
        }
      );

      api.registerValueTransformer(
        "more-topics-tabs",
        ({ value: tabs, context }) => {
          if (!inDocSimpleMode(siteSettings, context.topic?.category)) {
            return tabs;
          }
          return tabs.filter((tab) => tab.id !== "suggested-topics");
        }
      );

      // Own replies should be visible immediately rather than flashing and
      // then getting swallowed back behind "Show xx comments". While
      // collapsed, the stream only has the OP loaded, so committing a reply
      // several posts ahead (post_number-wise) leaves a gap of un-fetched
      // posts between the OP and the new reply. Force an authoritative
      // reload of that window instead of trying to reconstruct it locally.
      api.onAppEvent("post:created", async (post) => {
        const postStream =
          post.topic?.postStream ??
          container.lookup("controller:topic")?.model?.postStream;
        if (
          !postStream ||
          !inDocSimpleMode(siteSettings, postStream.topic?.category)
        ) {
          return;
        }

        const state = getState(postStream);
        if (state.expanded === false) {
          const index = postStream.posts.indexOf(post);
          const previousPost = index > 0 ? postStream.posts[index - 1] : null;
          const hasGap =
            previousPost && post.post_number > previousPost.post_number + 1;

          state.hiddenIds = [];
          state.hiddenCount = 0;
          state.expanded = true;

          if (hasGap) {
            await postStream.refresh({
              nearPost: post.post_number,
              forceLoad: true,
            });
          }
        }

        schedule("afterRender", () => {
          DiscourseURL.jumpToPost(post.post_number, { jumpEnd: true });
        });
      });

      api.renderAfterWrapperOutlet("post-links", DocSimpleModeToggle);
    });
  },
};
