# frozen_string_literal: true

module Jobs
  class DocCategoriesAutoIndex < ::Jobs::Base
    def execute(args)
      action = args[:action]
      raise Discourse::InvalidParameters.new(:action) if action.blank?

      case action
      when "add"
        topic_id = args[:topic_id]
        raise Discourse::InvalidParameters.new(:topic_id) if topic_id.blank?
        DocCategories::AutoIndexer::AddTopic.call(params: { topic_id: topic_id })
      when "remove"
        topic_id = args[:topic_id]
        raise Discourse::InvalidParameters.new(:topic_id) if topic_id.blank?
        DocCategories::AutoIndexer::RemoveTopic.call(params: { topic_id: topic_id })
      when "sync"
        index_id = args[:index_id]
        raise Discourse::InvalidParameters.new(:index_id) if index_id.blank?
        DocCategories::AutoIndexer::Sync.call(params: { index_id: index_id })
      else
        raise Discourse::InvalidParameters.new(:action)
      end
    end
  end
end
