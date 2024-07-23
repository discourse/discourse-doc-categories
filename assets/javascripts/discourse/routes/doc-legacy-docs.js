import { service } from "@ember/service";
import { isPresent } from "@ember/utils";
import DiscourseURL from "discourse/lib/url";
import DiscourseRoute from "discourse/routes/discourse";
import { samePrefix } from "discourse-common/lib/get-url";

export default class DocLegacyDocsRoute extends DiscourseRoute {
  @service router;
  @service siteSettings;

  beforeModel(transition) {
    const queryParams = new URLSearchParams(
      transition.intent.url.split("?")?.[1]
    );

    // if there is a `topic` parameter provided. try to redirect to the corresponding topic
    const topicId = queryParams.get("topic");

    // remove the topic param from the list
    queryParams.delete("topic");

    if (topicId) {
      this.redirectToTopic(transition, topicId, queryParams);
      return;
    }

    // if a topic was not provided try to redirect to the default homepage, if one was set
    this.redirectToHomepage(transition, queryParams);
  }

  redirectToTopic(transition, topicId, queryParams) {
    if (Number.isInteger(parseInt(topicId, 10))) {
      let url = `/t/${topicId}${this.prepareQueryParams(queryParams)}`;

      transition.abort();
      DiscourseURL.routeTo(url);
    } else {
      this.router.replaceWith("/404");
    }
  }

  redirectToHomepage(transition, queryParams) {
    // if a topic was not provided try to redirect to the default homepage, if one was set
    if (isPresent(this.siteSettings.doc_categories_homepage)) {
      transition.abort();

      const targetURL = `${
        this.siteSettings.doc_categories_homepage
      }${this.prepareQueryParams(queryParams)}`;

      if (DiscourseURL.isInternal(targetURL) && samePrefix(targetURL)) {
        DiscourseURL.routeTo(targetURL);
      } else {
        DiscourseURL.redirectTo(targetURL);
      }

      return;
    }

    // fallback to 404
    this.router.replaceWith("/404");
  }

  prepareQueryParams(queryParams) {
    const urlParams = queryParams.toString();
    if (isPresent(urlParams)) {
      return `?${urlParams}`;
    }

    return "";
  }
}
