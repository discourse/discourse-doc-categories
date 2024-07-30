import { withPluginApi } from "discourse/lib/plugin-api";
import Category from "discourse/models/category";
import DocCategorySettings from "../components/doc-category-settings";
import DocCategorySidebarPanel, {
  generateSectionName,
} from "../lib/doc-category-sidebar-panel";

export default {
  name: "doc-categories",
  initialize(container) {
    const docCategorySidebar = container.lookup("service:doc-category-sidebar");

    withPluginApi("1.34.0", (api) => {
      // add fields for the settings in the category edit page
      api.renderInOutlet("category-custom-settings", DocCategorySettings);

      // add docs panel to the sidebar
      api.addSidebarPanel(DocCategorySidebarPanel);

      // override how the sections in the docs sidebar ar expanded when first rendered
      // if the sections contains an active link, the section is expanded
      api.registerBehaviorTransformer(
        "sidebar-section-set-expanded-state",
        ({ context, next }) => {
          if (docCategorySidebar.isVisible) {
            const { sectionName } = context;

            if (
              docCategorySidebar.activeSectionInfo &&
              generateSectionName(
                docCategorySidebar.activeSectionInfo.sectionConfig
              ) === sectionName
            ) {
              // the section will be expanded, if active
              return;
            }
          }

          // default behavior
          next();
        }
      );

      // tries to activate the docs sidebar as soon as possible.
      // this is done to prevent that the default sidebar flashes on the screen before the docs sidebar is activated
      api.registerBehaviorTransformer(
        "route-application-activate",
        ({ context, next }) => {
          next();

          if (context.transition?.isAborted) {
            return;
          }

          let route = context.transition?.to;
          let category;
          do {
            category =
              context.transition?.resolvedModels?.[route.name]?.category;
            route = route.parent;
          } while (route && !(category instanceof Category));

          docCategorySidebar.maybeForceDocsSidebar({ category });
        }
      );
    });
  },
};
