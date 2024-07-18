import { getOwnerWithFallback } from "discourse-common/lib/get-owner";

export default function () {
  const siteSettings = getOwnerWithFallback(this).lookup(
    "service:site-settings"
  );

  if (!siteSettings.docs_legacy_enabled) {
    return;
  }

  const site = getOwnerWithFallback(this).lookup("service:site");
  const docsPath = site.docs_legacy_path || "docs";

  this.route("doc-legacy-docs", { path: "/" + docsPath }, function () {
    this.route("index", { path: "/" });
  });
}
