# frozen_string_literal: true

module DocCategories
  class CategoryIndexManager
    def initialize(category)
      @category = category
    end

    def assign!(topic_id)
      topic_id = normalize_topic_id(topic_id)

      if topic_id.nil?
        if (index = DocCategories::Index.find_by(category_id: category.id))
          index.destroy!
          category.reload
          enqueue_refresh
          return true
        end

        return false
      end

      topic = ::Topic.find_by(id: topic_id)
      return false unless valid_index_topic?(topic)

      index = DocCategories::Index.find_or_initialize_by(category_id: category.id)
      return false if index.index_topic_id == topic.id

      index.index_topic = topic
      index.save!
      enqueue_refresh

      true
    end

    private

    attr_reader :category

    def normalize_topic_id(value)
      return nil if value.blank?

      id = value.to_i
      id.positive? ? id : nil
    end

    def valid_index_topic?(topic)
      return false if topic.blank?
      return false if topic.category_id != category.id
      return false if topic.private_message?
      return false if topic.trashed?

      true
    end

    def enqueue_refresh
      ::Jobs.enqueue(:doc_categories_refresh_index, category_id: category.id)
    end
  end
end
