import { cached } from "@glimmer/tracking";
import { trustHTML } from "@ember/template";
import { getOwnerWithFallback } from "discourse/lib/get-owner";
import getURL, { samePrefix } from "discourse/lib/get-url";
import BaseCustomSidebarSection from "discourse/lib/sidebar/base-custom-sidebar-section";
import BaseCustomSidebarSectionLink from "discourse/lib/sidebar/base-custom-sidebar-section-link";
import DiscourseURL from "discourse/lib/url";
import { escapeExpression, unicodeSlugify } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";
import { SIDEBAR_DOCS_PANEL } from "../services/doc-category-sidebar.js";

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

      const sections = this.docCategorySidebar.sectionsConfig;
      const configs =
        "items" in BaseCustomSidebarSection.prototype
          ? sections
          : sections.flatMap(flattenDocsSection);
      const names = new Map();

      return configs.map((config) =>
        prepareDocsSection({ config, router, names })
      );
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
          (assembleCategoryFilter("", active, 1) ?? `category:${active.id}`);
      }

      const params = {
        filter: escapeExpression(filter),
        content_search_url: getURL(
          `/search?q=${encodeURIComponent(filter + categoryFilter)}`
        ),
        site_search_url: getURL(`/search?q=${encodeURIComponent(filter)}`),
      };

      return trustHTML(
        i18n("doc_categories.sidebar.filter.no_results.description", params)
      );
    }
  };

export default sidebarPanelClassBuilder;

function flattenDocsSection(section) {
  if (!section.items) {
    return [section];
  }
  const links = section.items.filter((item) => item.type === "link");
  const children = section.items.filter((item) => item.type === "section");
  return [
    ...(links.length ? [{ ...section, links }] : []),
    ...children.flatMap(flattenDocsSection),
  ];
}

function uniqueName(name, names) {
  const count = (names.get(name) ?? 0) + 1;
  names.set(name, count);
  return count === 1 ? name : `${name}--${count}`;
}

function prepareDocsSection({ config, router, names }) {
  const name = uniqueName(
    config.text
      ? `${SIDEBAR_DOCS_PANEL}__${unicodeSlugify(config.text)}`
      : `${SIDEBAR_DOCS_PANEL}::root`,
    names
  );

  return class extends BaseCustomSidebarSection {
    name = name;

    get title() {
      return config.text;
    }

    get text() {
      return config.text;
    }

    get items() {
      const sectionNames = new Map();
      const linkNames = new Map();

      return config.items?.map((item) => {
        if (item.type === "section") {
          return {
            type: "section",
            section: prepareDocsSection({
              config: item,
              router,
              names: sectionNames,
            }),
          };
        }

        return { type: "link", link: this.#buildLink(item, linkNames) };
      });
    }

    get links() {
      const linkNames = new Map();
      return (config.links ?? []).map((link) =>
        this.#buildLink(link, linkNames)
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

    #buildLink(data, linkNames) {
      const linkName = uniqueName(
        `${this.name}___${unicodeSlugify(data.text)}`,
        linkNames
      );
      return new DocCategorySidebarSectionLink({
        data,
        name: linkName,
        router,
      });
    }
  };
}

class DocCategorySidebarSectionLink extends BaseCustomSidebarSectionLink {
  name;

  #data;
  #router;

  constructor({ data, name, router }) {
    super(...arguments);

    this.#data = data;
    this.name = name;
    this.#router = router;
  }

  get currentWhen() {
    if (!DiscourseURL.isInternal(this.href) || !samePrefix(this.href)) {
      return false;
    }

    const currentTopicRouteInfo = this.#router.currentRoute?.find(
      (route) => route.name === "topic"
    );

    if (!currentTopicRouteInfo) {
      return false;
    }

    const { slug, id } = currentTopicRouteInfo.params;

    const path = new URL(this.href, window.location.origin).pathname;
    return (
      path === `/t/${slug}/${id}` ||
      path === `/t/${slug}` ||
      path === `/t/${id}`
    );
  }

  get classNames() {
    return "docs-sidebar-nav-link";
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

  get keywords() {
    return {
      navigation: this.#data.text.toLowerCase().split(/\s+/g),
    };
  }
}

function assembleCategoryFilter(filter, category, level) {
  if (!category) {
    return filter;
  }

  if (level > 2) {
    return null;
  }

  if (category.parentCategory) {
    return assembleCategoryFilter(
      ":" + category.slug,
      category.parentCategory,
      level + 1
    );
  } else {
    return "#" + category.slug + filter;
  }
}
