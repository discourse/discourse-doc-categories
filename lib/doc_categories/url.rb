# frozen_string_literal: true

module ::DocCategories::Url
  def self.extract_topic_id_from_url(url)
    return unless route = Discourse.route_for(url)
    return unless route[:controller] == "topics" && route[:action] == "show"

    topic_id = route[:topic_id] || route[:id]
    topic_id.to_i
  end
end
