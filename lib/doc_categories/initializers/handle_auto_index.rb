# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class HandleAutoIndex < Initializer
      def apply
        plugin.on(:topic_created) { |topic, _opts, _user| enqueue_add(topic) }
        plugin.on(:topic_recovered) { |topic| enqueue_add(topic) }
        plugin.on(:topic_trashed) { |topic| enqueue_remove(topic) }
        plugin.on(:topic_destroyed) { |topic, _user| enqueue_remove(topic) }

        # When a topic's visibility changes (listed/unlisted), re-evaluate its
        # auto-index eligibility. Core triggers :topic_status_updated from
        # Topic#update_status (topic.rb) with (topic, status_name, enabled).
        plugin.on(:topic_status_updated) do |topic, status, enabled|
          next if status != "visible"
          enabled ? enqueue_add(topic) : enqueue_remove(topic)
        end

        # Capture bound references to the private helpers so that the
        # add_model_callback block (where `self` is the Topic instance,
        # not the Initializer) can still invoke them through the closure.
        add_handler = method(:enqueue_add)
        remove_handler = method(:enqueue_remove)

        # Topic#make_banner! and Topic#remove_banner! change the archetype
        # directly and call save without triggering any DiscourseEvent, so
        # an after_save callback is the only way to detect archetype changes.
        # This also covers conversions to/from private messages.
        plugin.add_model_callback(:topic, :after_save) do
          next unless saved_change_to_archetype?

          prev_archetype, new_archetype = saved_change_to_archetype

          if new_archetype == Archetype.default && category_id.present?
            # Topic became a regular topic (e.g., remove_banner!, PM conversion).
            # Re-evaluate it for auto-indexing.
            add_handler.call(self)
          elsif prev_archetype == Archetype.default
            # Topic left the regular archetype (e.g., make_banner!, convert to PM).
            # Remove any auto-indexed links for it. No category_id guard needed
            # because PM conversion clears category_id, but we still need to
            # clean up existing auto-indexed links.
            remove_handler.call(self)
          end
        end
      end

      private

      def enqueue_add(topic)
        return if !topic&.category_id
        return if !has_auto_index_for_category?(topic.category_id)

        ::Jobs.enqueue(:doc_categories_auto_index, action: "add", topic_id: topic.id)
      end

      def enqueue_remove(topic)
        return if !topic
        ::Jobs.enqueue(:doc_categories_auto_index, action: "remove", topic_id: topic.id)
      end

      def has_auto_index_for_category?(category_id)
        return true if auto_index_exists_for?(category_id)

        # A topic may be in a subcategory of a doc category that includes subcategories
        parent_id = ::Category.where(id: category_id).pick(:parent_category_id)
        parent_id && auto_index_exists_for?(parent_id)
      end

      def auto_index_exists_for?(cat_id)
        DocCategories::Index
          .joins(:sidebar_sections)
          .where(
            category_id: cat_id,
            index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
            sidebar_sections: {
              auto_index: true,
            },
          )
          .exists?
      end
    end
  end
end
