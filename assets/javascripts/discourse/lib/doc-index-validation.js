import { i18n } from "discourse-i18n";

export default function validateDocIndexSections(sections) {
  const errors = new Set();

  for (let i = 0; i < sections.length; i++) {
    const section = sections[i];
    // First section is allowed to have an empty title (not collapsible in sidebar)
    if (i > 0 && !section.title?.trim()) {
      errors.add(
        i18n(
          "doc_categories.category_settings.index_editor.validation_empty_section_title"
        )
      );
    }
    if (section.links.length === 0 && !section.autoIndex) {
      errors.add(
        i18n(
          "doc_categories.category_settings.index_editor.validation_empty_section"
        )
      );
    }
    for (const link of section.links) {
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
