import { getOwnerWithFallback } from "discourse-common/lib/get-owner";

export default function () {
  const site = getOwnerWithFallback(this).lookup("service:site");

  const docsPath = site.docs_legacy_path;

  if (!docsPath) {
    return;
  }

  this.route("doc-legacy-docs", { path: "/" + docsPath });
  this.route("doc-legacy-kb-xplr", { path: "/knowledge-explorer" });
}
