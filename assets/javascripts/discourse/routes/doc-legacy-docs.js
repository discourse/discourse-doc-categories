import { service } from "@ember/service";
import { isPresent } from "@ember/utils";
import DiscourseURL from "discourse/lib/url";
import DiscourseRoute from "discourse/routes/discourse";

export default class DocLegacyDocs extends DiscourseRoute {
  @service router;

  beforeModel(transition) {
    const queryParams = new URLSearchParams(
      transition.intent.url.split("?")?.[1]
    );

    const topicId = queryParams.get("topic");

    if (!topicId || !Number.isInteger(parseInt(topicId, 10))) {
      this.router.replaceWith("/404");
      return;
    }

    transition.abort();

    let url = `/t/${topicId}`;
    const urlParams = queryParams.toString();
    if (isPresent(urlParams)) {
      url += `?${urlParams}`;
    }

    DiscourseURL.redirectTo(url);
  }
}
