import { modifier } from "ember-modifier";

export default modifier((element, [isSaving]) => {
  if (!isSaving) {
    return;
  }

  // The category's Save/Reset banner is outside the tab's form section.
  const page = element.closest(".edit-category-page") || element;
  const wasInert = page.inert;
  page.inert = true;
  return () => {
    page.inert = wasInert;
  };
});
