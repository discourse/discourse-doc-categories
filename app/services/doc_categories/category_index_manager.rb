# frozen_string_literal: true

module DocCategories
  class CategoryIndexManager
    include Service::Base

    options { attribute :expected_index_topic_id, :integer }

    params do
      attribute :category_id, :integer
      attribute :topic_id

      validates :category_id, presence: true

      def normalized_topic_id
        value = topic_id.presence&.to_i
        value if value&.positive? || value == DocCategories::Index::INDEX_TOPIC_ID_DIRECT
      end
    end

    transaction do
      model :category
      model :index, optional: true
      policy :index_editor_enabled

      only_if(:assigning_topic_mode) do
        model :topic
        policy :valid_index_topic
      end

      model :index_change, :plan_index_change
      only_if(:removing_index) { step :remove_index }
      only_if(:assigning_index) do
        only_if(:replacing_direct_sections) { step :remove_direct_sections }
        model :saved_index, :save_index
      end
    end

    only_if(:topic_index_assigned) { step :schedule_refresh }
    only_if(:index_changed) { step :publish_changes }

    private

    def fetch_category(params:)
      ::Category.lock.find_by(id: params.category_id)
    end

    def fetch_index(category:)
      DocCategories::Index.find_by(category: category)
    end

    def index_editor_enabled(params:, index:)
      params.normalized_topic_id != DocCategories::Index::INDEX_TOPIC_ID_DIRECT ||
        SiteSetting.doc_categories_index_editor || index&.mode_direct?
    end

    def assigning_topic_mode(params:)
      params.normalized_topic_id&.positive?
    end

    def fetch_topic(params:)
      ::Topic.find_by(id: params.normalized_topic_id)
    end

    def valid_index_topic(topic:, category:)
      topic.category_id == category.id && !topic.private_message? && !topic.trashed? &&
        !topic.shared_draft
    end

    def plan_index_change(params:, index:, options:)
      if options.expected_index_topic_id && index&.index_topic_id != options.expected_index_topic_id
        return :unchanged
      end

      topic_id = params.normalized_topic_id
      return :remove if topic_id.nil? && index
      return :assign if topic_id != index&.index_topic_id

      :unchanged
    end

    def removing_index(index_change:)
      index_change == :remove
    end

    def remove_index(index:, category:)
      index.destroy!
      category.reload
    end

    def replacing_direct_sections(params:, index:)
      assigning_topic_mode(params: params) && index&.mode_direct?
    end

    def remove_direct_sections(index:)
      index.sidebar_sections.destroy_all
    end

    def assigning_index(index_change:)
      index_change == :assign
    end

    def save_index(params:, category:, index:)
      index_topic_id = params.normalized_topic_id
      return Index.create(category:, index_topic_id:) if index.nil?

      index.update(index_topic_id:)
      index
    end

    def schedule_refresh(category:)
      DB.after_commit { ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category.id) }
    end

    def publish_changes(category:)
      DocCategories::Action::PublishSidebarChanges.call(category_ids: [category.id])
    end

    def topic_index_assigned(index_change:, params:)
      index_change == :assign && assigning_topic_mode(params:)
    end

    def index_changed(index_change:)
      index_change != :unchanged
    end
  end
end
