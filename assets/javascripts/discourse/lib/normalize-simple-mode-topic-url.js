export default function normalizeSimpleModeTopicUrl(topicUrl) {
  if (!topicUrl) {
    return;
  }

  const normalizedUrl = `${topicUrl}${window.location.search}`;

  if (
    `${window.location.pathname}${window.location.search}` === normalizedUrl
  ) {
    return;
  }

  history.replaceState(null, "", normalizedUrl);
}
