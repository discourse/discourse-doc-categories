import { i18n } from "discourse-i18n";

export default function validateDocIndexSections(sections) {
  const errors = [];

  for (const section of sections) {
    if (!section.title?.trim()) {
      errors.push(
        i18n(
          "doc_categories.category_settings.index_editor.validation_empty_section_title"
        )
      );
    }
    if (section.links.length === 0 && !section.autoIndex) {
      errors.push(
        i18n(
          "doc_categories.category_settings.index_editor.validation_empty_section"
        )
      );
    }
    for (const link of section.links) {
      if (!link.title?.trim() && link.type !== "topic") {
        errors.push(
          i18n(
            "doc_categories.category_settings.index_editor.validation_empty_link_title"
          )
        );
      }
      if (!link.href?.trim()) {
        errors.push(
          i18n(
            "doc_categories.category_settings.index_editor.validation_empty_link_url"
          )
        );
      }
    }
  }

  return errors;
}
