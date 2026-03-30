export const DOC_ORIGINAL_STREAM = Symbol("doc-original-stream");

export default function isDocCategory(category) {
  return !!category?.doc_index_topic_id;
}
