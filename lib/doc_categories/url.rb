# frozen_string_literal: true

module ::DocCategories::Url
  def self.extract_topic_id_from_url(url)
    return unless route = Discourse.route_for(url)
    return unless route[:controller] == "topics" && route[:action] == "show"

    topic_id = (route[:topic_id] || route[:id]).to_i
    topic_id if topic_id.positive?
  end
end
