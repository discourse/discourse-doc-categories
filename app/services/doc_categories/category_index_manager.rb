# frozen_string_literal: true

module DocCategories
  class CategoryIndexManager
    include Service::Base

    params do
      attribute :category_id, :integer
      attribute :topic_id

      validates :category_id, presence: true

      def normalized_topic_id
        value = topic_id.presence&.to_i
        value if value&.positive? || value == DocCategories::Index::INDEX_TOPIC_ID_DIRECT
      end
    end

    model :category
    model :index, optional: true

    only_if(:assigning_topic_mode) do
      model :topic
      policy :valid_index_topic
    end

    only_if(:changing_index) do
      transaction do
        only_if(:removing_index) { step :remove_index }
        only_if(:replacing_direct_sections) { step :remove_direct_sections }
        only_if(:assigning_index) { model :saved_index, :save_index }
      end

      only_if(:assigning_topic_mode) { step :schedule_refresh }
      step :publish_changes
    end

    private

    def fetch_category(params:)
      ::Category.find_by(id: params.category_id)
    end

    def fetch_index(category:)
      DocCategories::Index.find_by(category: category)
    end

    def assigning_topic_mode(params:)
      params.normalized_topic_id&.positive?
    end

    def fetch_topic(params:)
      ::Topic.find_by(id: params.normalized_topic_id)
    end

    def valid_index_topic(topic:, category:)
      topic.category_id == category.id && !topic.private_message? && !topic.trashed?
    end

    def changing_index(params:, index:)
      params.normalized_topic_id != index&.index_topic_id ||
        (params.normalized_topic_id.nil? && index.present?)
    end

    def removing_index(params:)
      params.normalized_topic_id.nil?
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

    def assigning_index(params:)
      params.normalized_topic_id.present?
    end

    def save_index(params:, category:, index:)
      record = index || DocCategories::Index.new(category: category)
      record.index_topic_id = params.normalized_topic_id
      record.save
      record
    end

    def schedule_refresh(category:)
      ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category.id)
    end

    def publish_changes(category:)
      Site.clear_cache
      category.publish_category
    end
  end
end
