import { i18n } from "discourse-i18n";
import {
  MAX_LINKS_PER_SECTION,
  MAX_SECTION_DEPTH,
  MAX_SECTIONS,
} from "./constants.js";
import {
  isIndexSection,
  sectionEntries,
  sectionLinks,
} from "./doc-index-tree.js";

export default function validateDocIndexSections(sections) {
  const errors = new Set();

  const entries = [...sectionEntries(sections)];
  if (entries.length > MAX_SECTIONS) {
    errors.add(
      i18n("doc_categories.category_settings.index_editor.section_limit", {
        count: MAX_SECTIONS,
      })
    );
  }

  for (const { section, ancestors } of entries) {
    const links = sectionLinks(section);
    const hasChildren = section.items?.some(isIndexSection);
    if (ancestors.length >= MAX_SECTION_DEPTH) {
      errors.add(
        i18n(
          "doc_categories.category_settings.index_editor.section_depth_limit",
          {
            count: MAX_SECTION_DEPTH,
          }
        )
      );
    }
    if (links.length > MAX_LINKS_PER_SECTION) {
      errors.add(
        i18n("doc_categories.category_settings.index_editor.link_limit", {
          count: MAX_LINKS_PER_SECTION,
        })
      );
    }
    // First section is allowed to have an empty title (not collapsible in sidebar)
    if ((section !== sections[0] || hasChildren) && !section.title?.trim()) {
      errors.add(
        i18n(
          "doc_categories.category_settings.index_editor.validation_empty_section_title"
        )
      );
    }
    if (links.length === 0 && !hasChildren && !section.autoIndex) {
      errors.add(
        i18n(
          "doc_categories.category_settings.index_editor.validation_empty_section"
        )
      );
    }
    for (const link of links) {
      if (!link.title?.trim() && link.type !== "topic") {
        errors.add(
          i18n(
            "doc_categories.category_settings.index_editor.validation_empty_link_title"
          )
        );
      }
      if (!link.href?.trim()) {
        errors.add(
          i18n(
            "doc_categories.category_settings.index_editor.validation_empty_link_url"
          )
        );
      }
    }
  }

  return [...errors];
}
