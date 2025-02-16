import { cached } from "@glimmer/tracking";
import { computed } from "@ember/object";
import { htmlSafe } from "@ember/template";
import { getOwnerWithFallback } from "discourse/lib/get-owner";
import getURL, { getAbsoluteURL, samePrefix } from "discourse/lib/get-url";
import BaseCustomSidebarSection from "discourse/lib/sidebar/base-custom-sidebar-section";
import BaseCustomSidebarSectionLink from "discourse/lib/sidebar/base-custom-sidebar-section-link";
import DiscourseURL from "discourse/lib/url";
import { escapeExpression, unicodeSlugify } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";
import { SIDEBAR_DOCS_PANEL } from "../services/doc-category-sidebar";

const sidebarPanelClassBuilder = (BaseCustomSidebarPanel) =>
  class DocCategorySidebarPanel extends BaseCustomSidebarPanel {
    key = SIDEBAR_DOCS_PANEL;
    hidden = true;
    displayHeader = true;
    expandActiveSection = true;
    scrollActiveLinkIntoView = true;

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
        i18n("doc_categories.sidebar.filter.no_results.description", params)
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
      return this.text
        ? `${SIDEBAR_DOCS_PANEL}__${unicodeSlugify(this.text)}`
        : `${SIDEBAR_DOCS_PANEL}::root`;
    }

    get title() {
      return this.#config.text;
    }

    get text() {
      return this.#config.text;
    }

    get links() {
      return this.sectionLinks.map(
        (sectionLinkData) =>
          new DocCategorySidebarSectionLink({
            data: sectionLinkData,
            panelName: this.name,
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
  #data;
  #panelName;
  #router;

  constructor({ data, panelName, router }) {
    super(...arguments);

    this.#data = data;
    this.#panelName = panelName;
    this.#router = router;
  }

  get currentWhen() {
    if (DiscourseURL.isInternal(this.href) && samePrefix(this.href)) {
      const topicRouteInfo = this.#router
        .recognize(this.href.replace(getAbsoluteURL("/"), "/"), "")
        .find((route) => route.name === "topic");

      const currentTopicRouteInfo = this.#router.currentRoute.find(
        (route) => route.name === "topic"
      );

      return (
        currentTopicRouteInfo &&
        currentTopicRouteInfo?.params?.id === topicRouteInfo?.params?.id
      );
    }

    return false;
  }

  get name() {
    return `${this.#panelName}___${unicodeSlugify(this.#data.text)}`;
  }

  get classNames() {
    const list = ["docs-sidebar-nav-link"];
    return list.join(" ");
  }

  get href() {
    return this.#data.href;
  }

  get text() {
    return this.#data.text;
  }

  get title() {
    return this.#data.text;
  }

  @computed("data.text")
  get keywords() {
    return {
      navigation: this.#data.text.toLowerCase().split(/\s+/g),
    };
  }

  get prefixType() {
    return "icon";
  }

  get prefixValue() {
    return "far-file";
  }
}
