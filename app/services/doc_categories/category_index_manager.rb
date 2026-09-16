# frozen_string_literal: true

module DocCategories
  class CategoryIndexManager
    include Service::Base

    params do
      attribute :category_id, :integer
      attribute :topic_id

      validates :category_id, presence: true
    end

    model :category
    step :normalize_topic_id

    only_if(:removing_index) do
      model :existing_index, :fetch_existing_index, optional: true
      step :remove_index
    end

    only_if(:assigning_direct_mode) { step :assign_direct }

    only_if(:assigning_topic_mode) do
      model :topic
      policy :valid_index_topic
      step :assign_topic
    end

    step :publish_changes

    private

    def fetch_category(params:)
      ::Category.find_by(id: params.category_id)
    end

    def normalize_topic_id(params:)
      value = params.topic_id

      if value.blank?
        context[:normalized_topic_id] = nil
        context[:action] = :remove
        return
      end

      id = value.to_i

      if id == DocCategories::Index::INDEX_TOPIC_ID_DIRECT
        context[:normalized_topic_id] = id
        context[:action] = :direct
      elsif id.positive?
        context[:normalized_topic_id] = id
        context[:action] = :topic
      else
        context[:normalized_topic_id] = nil
        context[:action] = :remove
      end
    end

    def removing_index
      context[:action] == :remove
    end

    def fetch_existing_index(category:)
      DocCategories::Index.find_by(category_id: category.id)
    end

    def remove_index(existing_index:, category:)
      return if existing_index.nil?

      existing_index.destroy!
      category.reload
      context[:changed] = true
    end

    def assigning_direct_mode
      context[:action] == :direct
    end

    def assign_direct(category:)
      index = DocCategories::Index.find_or_initialize_by(category_id: category.id)
      return if index.mode_direct?

      index.index_topic_id = DocCategories::Index::INDEX_TOPIC_ID_DIRECT
      index.save!
      context[:changed] = true
    end

    def assigning_topic_mode
      context[:action] == :topic
    end

    def fetch_topic
      ::Topic.find_by(id: context[:normalized_topic_id])
    end

    def valid_index_topic(topic:, category:)
      return false if topic.category_id != category.id
      return false if topic.private_message?
      return false if topic.trashed?

      true
    end

    def assign_topic(category:, topic:)
      index = DocCategories::Index.find_or_initialize_by(category_id: category.id)
      return if index.index_topic_id == topic.id

      # Clear stale direct-mode sections before switching to topic mode
      index.sidebar_sections.destroy_all if index.persisted? && index.mode_direct?

      index.index_topic = topic
      index.save!
      ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category.id)
      context[:changed] = true
    end

    def publish_changes(category:)
      return unless context[:changed]

      Site.clear_cache
      category.publish_category
    end
  end
end
