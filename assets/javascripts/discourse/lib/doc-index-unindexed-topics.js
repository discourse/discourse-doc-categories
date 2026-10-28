import { tracked } from "@glimmer/tracking";
import { cancel } from "@ember/runloop";
import { ajax } from "discourse/lib/ajax";
import discourseDebounce from "discourse/lib/debounce";
import { withoutPrefix } from "discourse/lib/get-url";
import DiscourseURL from "discourse/lib/url";

// Mirror DocCategories::Index limits, which Apply enforces.
export const MAX_LINKS_PER_SECTION = 200;
export const MAX_SECTIONS = 50;
const MAX_HREF_LENGTH = 2000;

const RECOUNT_DELAY = 500;
const TOPIC_PATH = /^\/t\/(?:[^/]*[^\d/][^/]*\/)?(\d+)(?:\/\d+)?\/?$/;

function sameSiteDraftHref(href) {
  if (!href?.trim()) {
    return null;
  }

  // Apply truncates hrefs before resolving their topic IDs.
  const normalized = [...href.trim()].slice(0, MAX_HREF_LENGTH).join("");
  try {
    const url = new URL(normalized, DiscourseURL.origin);
    if (url.hostname !== new URL(DiscourseURL.origin).hostname) {
      return null;
    }
  } catch {
    return null;
  }
  return normalized;
}

export function topicIdFromHref(href) {
  const normalized = sameSiteDraftHref(href);
  if (!normalized || !DiscourseURL.isInternal(normalized)) {
    return null;
  }

  const pathname = new URL(normalized, DiscourseURL.origin).pathname;
  const match = TOPIC_PATH.exec(withoutPrefix(pathname));
  return match ? parseInt(match[1], 10) : null;
}

/**
 * The topic ids the draft's links carry, and the hrefs of links without one
 * for the server to resolve the way Apply does. Sorted and unique, so equal
 * drafts compare equal. A link still being edited has no settled href yet.
 */
export function draftTopicReferences(sections) {
  const topicIds = new Set();
  const hrefs = new Set();

  for (const section of sections) {
    for (const link of section.links) {
      const topicId = Number(link.topic_id);
      if (Number.isInteger(topicId) && topicId > 0) {
        topicIds.add(topicId);
      } else if (!link.isEditing) {
        const href = sameSiteDraftHref(link.href);
        if (href) {
          hrefs.add(href);
        }
      }
    }
  }

  return {
    topicIds: [...topicIds].sort((a, b) => a - b),
    hrefs: [...hrefs].sort(),
  };
}

export function draftTopicIds(sections) {
  const { topicIds, hrefs } = draftTopicReferences(sections);
  const ids = new Set(topicIds);
  for (const href of hrefs) {
    const id = topicIdFromHref(href);
    if (id) {
      ids.add(id);
    }
  }
  return ids;
}

export async function fetchUnindexedTopics(
  categoryId,
  { references, includeSubcategories, search, page = 0, countOnly = false }
) {
  const data = {
    exclude_topic_ids: references.topicIds,
    exclude_hrefs: references.hrefs,
    include_subcategories: !!includeSubcategories,
    page,
  };
  if (search?.trim()) {
    data.search = search.trim();
  }
  if (countOnly) {
    data.limit = 0;
  }

  const response = await ajax(
    `/doc-categories/indexes/${categoryId}/unindexed_topics`,
    {
      type: "POST",
      contentType: "application/json",
      data: JSON.stringify(data),
    }
  );

  const topics = response.topics || [];
  const totalCount = response.total_count ?? 0;
  return {
    topics,
    totalCount,
    hasMore: topics.length > 0 && (page + 1) * response.per_page < totalCount,
  };
}

/**
 * Counts the topics a draft leaves out, asking again only when what the draft
 * points at or the scope changes, so reordering and retitling stay local.
 */
export class UnindexedTopicsCounter {
  /** Stale while `isLoading`: it may decide visibility, never a shown number. */
  @tracked count = null;
  @tracked isLoading = false;

  #categoryId;
  #key = null;
  #sequence = 0;
  #timer = null;
  #destroyed = false;

  constructor(categoryId) {
    this.#categoryId = categoryId;
  }

  update(query, { force = false, immediate = false } = {}) {
    if (this.#destroyed || !this.#categoryId) {
      return;
    }

    const key = JSON.stringify([
      query.references.topicIds,
      query.references.hrefs,
      !!query.includeSubcategories,
    ]);
    if (key === this.#key && !force) {
      return;
    }
    this.#key = key;
    this.isLoading = true;
    const sequence = ++this.#sequence;

    cancel(this.#timer);
    if (immediate) {
      this.#recount(query, sequence);
    } else {
      this.#timer = discourseDebounce(
        this,
        this.#recount,
        query,
        sequence,
        RECOUNT_DELAY
      );
    }
  }

  teardown() {
    this.#destroyed = true;
    cancel(this.#timer);
  }

  async #recount(query, sequence) {
    const isCurrent = () => !this.#destroyed && sequence === this.#sequence;

    try {
      const { totalCount } = await fetchUnindexedTopics(this.#categoryId, {
        ...query,
        countOnly: true,
      });
      if (isCurrent()) {
        this.count = totalCount;
      }
    } catch {
      // Advisory only: a failed count hides the tip rather than raising an error.
      if (isCurrent()) {
        this.count = null;
        this.#key = null;
      }
    } finally {
      if (isCurrent()) {
        this.isLoading = false;
      }
    }
  }
}
