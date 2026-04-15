/**
 * Determines whether the cursor is above or below the vertical midpoint
 * of the element that triggered the event. Used by drag-and-drop handlers
 * to decide insertion position (before vs. after the target).
 */
export function isAboveElement(event) {
  event.preventDefault();
  const domRect = event.currentTarget.getBoundingClientRect();
  return event.clientY - domRect.top < domRect.height / 2;
}
