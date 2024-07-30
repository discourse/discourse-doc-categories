import { cached } from "@glimmer/tracking";
import { computed } from "@ember/object";
import { htmlSafe } from "@ember/template";
import BaseCustomSidebarSection from "discourse/lib/sidebar/base-custom-sidebar-section";
import BaseCustomSidebarSectionLink from "discourse/lib/sidebar/base-custom-sidebar-section-link";
import DiscourseURL from "discourse/lib/url";
import { escapeExpression, unicodeSlugify } from "discourse/lib/utilities";
import { getOwnerWithFallback } from "discourse-common/lib/get-owner";
import getURL, {
  getAbsoluteURL,
  samePrefix,
} from "discourse-common/lib/get-url";
import I18n from "discourse-i18n";
import { SIDEBAR_DOCS_PANEL } from "../services/doc-category-sidebar";

const sidebarPanelClassBuilder = (BaseCustomSidebarPanel) =>
  class DocCategorySidebarPanel extends BaseCustomSidebarPanel {
    key = SIDEBAR_DOCS_PANEL;
    hidden = true;
    displayHeader = true;

    get docCategorySidebar() {
      return getOwnerWithFallback(this).lookup("service:doc-category-sidebar");
    }

    @cached
    get sections() {
      const router = getOwnerWithFallback(this).lookup("service:router");

      return this.docCategorySidebar.sectionsConfig.map((config) => {
        return prepareDocsSection({ config, router });
      });
    }

    get filterable() {
      return !this.docCategorySidebar.loading;
    }

    filterNoResultsDescription(filter) {
      const active = this.docCategorySidebar.activeCategory;
      let categoryFilter = "";

      if (this.docCategorySidebar.activeCategory) {
        categoryFilter =
          " " +
          (this.#assembleCategoryFilter("", active, 1) ??
            `category:${active.id}`);
      }

      const params = {
        filter: escapeExpression(filter),
        content_search_url: getURL(
          `/search?q=${encodeURIComponent(filter + categoryFilter)}`
        ),
        site_search_url: getURL(`/search?q=${encodeURIComponent(filter)}`),
      };

      return htmlSafe(
        I18n.t("doc_categories.sidebar.filter.no_results.description", params)
      );
    }

    #assembleCategoryFilter(filter, category, level) {
      if (!category) {
        return filter;
      }

      if (level > 2) {
        return null;
      }

      if (category.parentCategory) {
        return this.#assembleCategoryFilter(
          ":" + category.slug,
          category.parentCategory,
          level + 1
        );
      } else {
        return "#" + category.slug + filter;
      }
    }
  };

export default sidebarPanelClassBuilder;

function prepareDocsSection({ config, router }) {
  return class extends BaseCustomSidebarSection {
    #config = config;

    get sectionLinks() {
      return this.#config.links;
    }

    get name() {
      return generateSectionName(this.#config);
    }

    get title() {
      return this.#config.text;
    }

    get text() {
      return this.#config.text;
    }

    get links() {
      return this.sectionLinks.map(
        (sectionLinkConfig) =>
          new DocCategorySidebarSectionLink({
            config: sectionLinkConfig,
            sectionName: this.name,
            router,
          })
      );
    }

    get displaySection() {
      return true;
    }

    get hideSectionHeader() {
      return !this.text;
    }

    get collapsedByDefault() {
      return false;
    }
  };
}

class DocCategorySidebarSectionLink extends BaseCustomSidebarSectionLink {
  #config;
  #sectionName;
  #router;

  constructor({ config, sectionName, router }) {
    super(...arguments);

    this.#config = config;
    this.#sectionName = sectionName;
    this.#router = router;
  }

  get active() {
    return isSectionLinkActive(this.#router, this.#config);
  }

  get name() {
    return generateSectionLinkName(this.#sectionName, this.#config);
  }

  get classNames() {
    const list = ["docs-sidebar-nav-link"];

    if (this.active) {
      list.push("active");
    }

    return list.join(" ");
  }

  get href() {
    return this.#config.href;
  }

  get text() {
    return this.#config.text;
  }

  get title() {
    return this.#config.text;
  }

  @computed("data.text")
  get keywords() {
    return {
      navigation: this.#config.text.toLowerCase().split(/\s+/g),
    };
  }
}

export function generateSectionName(config) {
  return config.text
    ? `${SIDEBAR_DOCS_PANEL}__${unicodeSlugify(config.text)}`
    : `${SIDEBAR_DOCS_PANEL}::root`;
}

export function generateSectionLinkName(sectionName, linkConfig) {
  return `${sectionName}___${unicodeSlugify(linkConfig.text)}`;
}

export function isSectionLinkActive(router, linkConfig) {
  if (DiscourseURL.isInternal(linkConfig.href) && samePrefix(linkConfig.href)) {
    const topicRouteInfo = router
      .recognize(linkConfig.href.replace(getAbsoluteURL("/"), "/"), "")
      .find((route) => route.name === "topic");

    const currentTopicRouteInfo = router.currentRoute?.find(
      (route) => route.name === "topic"
    );

    return (
      !!currentTopicRouteInfo &&
      currentTopicRouteInfo?.params?.id === topicRouteInfo?.params?.id
    );
  }

  return false;
}
