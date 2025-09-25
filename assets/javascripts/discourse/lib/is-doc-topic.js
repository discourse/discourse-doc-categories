export function isDocTopic(topic) {
  if (!topic) {
    return false;
  }

  if (topic.doc_topic) {
    return true;
  }

  const category = topic.category;
  if (!category) {
    return false;
  }

  if (Array.isArray(category.doc_category_index)) {
    return category.doc_category_index.length > 0;
  }

  const customFields = category.custom_fields;
  if (customFields && customFields.doc_category_index_topic) {
    return true;
  }

  return false;
}
