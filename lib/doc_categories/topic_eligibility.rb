# frozen_string_literal: true

module DocCategories
  module TopicEligibility
    def self.categories(category_id)
      ::Category.where(id: category_id).or(::Category.where(read_restricted: false))
    end

    # Sidebar structures are shared without a per-reader guardian.
    def self.allowed?(topic, category_id:)
      !topic.private_message? &&
        (topic.category_id == category_id || topic.category&.read_restricted? == false)
    end
  end
end
