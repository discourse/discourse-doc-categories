import { tracked } from "@glimmer/tracking";

// Per-postStream state stored via Symbol so it survives `updateFromJson` calls
// against the same postStream instance, but is naturally scoped to a topic
// (since each topic gets a fresh postStream).
const STATE = Symbol("doc-simple-mode-state");
const INTERCEPTED = Symbol("doc-simple-mode-intercepted");

class DocSimpleModeState {
  // `undefined` means the state has not been initialized yet for this
  // postStream (no transformer run has happened).
  @tracked expanded;

  // Count of post IDs currently hidden behind the toggle. Tracked so the
  // component reactively updates when MessageBus arrivals stash more IDs here.
  @tracked hiddenCount = 0;

  hiddenIds = [];
}

export function getState(postStream) {
  if (!postStream[STATE]) {
    postStream[STATE] = new DocSimpleModeState();
  }
  return postStream[STATE];
}

export function isDocCategory(category) {
  return !!category?.doc_index_topic_id;
}

export function inDocSimpleMode(siteSettings, category) {
  return siteSettings.doc_categories_simple_mode && isDocCategory(category);
}

// Collapses the postStream to OP only. Records the IDs we removed in state
// so they can be restored on expand or kept hidden when MessageBus appends
// more posts.
export function collapseStream(postStream) {
  const opPost = postStream.posts.find((p) => p.post_number === 1);
  if (!opPost) {
    return;
  }

  const state = getState(postStream);
  state.hiddenIds = postStream.stream.filter((id) => id !== opPost.id);
  state.hiddenCount = state.hiddenIds.length;

  postStream.stream.splice(0, postStream.stream.length, opPost.id);
  postStream.posts.splice(0, postStream.posts.length, opPost);

  state.expanded = false;
}

// Restores the stream to the full set: OP, then previously hidden IDs (in
// their original order), then any IDs added while collapsed (e.g. live
// arrivals not captured by the interceptor for any reason).
export function expandStream(postStream) {
  const opPost = postStream.posts.find((p) => p.post_number === 1);
  if (!opPost) {
    return;
  }

  const state = getState(postStream);
  const currentExtras = postStream.stream.filter((id) => id !== opPost.id);
  const fullStream = [
    opPost.id,
    ...state.hiddenIds,
    ...currentExtras.filter((id) => !state.hiddenIds.includes(id)),
  ];

  postStream.stream.splice(0, postStream.stream.length, ...fullStream);

  const restoredPosts = fullStream
    .map((id) => postStream.findLoadedPost(id))
    .filter(Boolean);
  postStream.posts.splice(0, postStream.posts.length, ...restoredPosts);

  state.hiddenIds = [];
  state.hiddenCount = 0;
  state.expanded = true;
}

// Wraps postStream.triggerNewPostsInStream so MessageBus arrivals during a
// collapsed view are stashed into hiddenIds (and counted toward the toggle
// label) instead of becoming visible. Idempotent per postStream instance.
export function attachNewPostInterceptor(postStream) {
  if (postStream[INTERCEPTED]) {
    return;
  }
  postStream[INTERCEPTED] = true;

  const original = postStream.triggerNewPostsInStream.bind(postStream);
  postStream.triggerNewPostsInStream = async (postIds, opts) => {
    const result = await original(postIds, opts);

    const state = getState(postStream);
    if (state.expanded !== false) {
      return result;
    }

    const opPost = postStream.posts.find((p) => p.post_number === 1);
    if (!opPost) {
      return result;
    }

    const extras = postStream.stream.filter((id) => id !== opPost.id);
    for (const id of extras) {
      if (!state.hiddenIds.includes(id)) {
        state.hiddenIds.push(id);
      }
    }
    state.hiddenCount = state.hiddenIds.length;

    postStream.stream.splice(0, postStream.stream.length, opPost.id);
    postStream.posts.splice(0, postStream.posts.length, opPost);

    return result;
  };
}
