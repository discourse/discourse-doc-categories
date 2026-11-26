# frozen_string_literal: true

module DocCategories
  module Action
    class ApplyPatch < Service::ActionBase
      option :patch

      def call
        operation = patch.operation
        if !IndexPatcher::OPERATIONS.key?(operation)
          raise ArgumentError, "Unknown index patch operation: #{operation.inspect}"
        end

        case operation
        when "add_section"
          add_section
        when "move_section"
          patch.section.update!(parent_section: patch.parent, position: insert_position)
        when "add_topic_links"
          append_topic_links(patch.section)
        when "remove_section"
          remove_section(patch.section)
        when "remove_topic_link"
          patch.links.each(&:destroy!)
        end
      end

      private

      def add_section
        index =
          patch.index ||
            Index.create!(category: patch.category, index_topic_id: Index::INDEX_TOPIC_ID_DIRECT)
        index.update!(index_topic_id: Index::INDEX_TOPIC_ID_DIRECT) if index.mode_none?
        section =
          index.sidebar_sections.create!(
            parent_section: patch.parent,
            title: patch.title,
            position: insert_position,
          )
        append_topic_links(section)
      end

      def append_topic_links(section)
        position = next_position(patch.section_items(section))
        patch.topics.each_with_index do |topic, offset|
          section.sidebar_links.create!(
            topic:,
            href: topic.relative_url,
            position: position + offset,
          )
        end
      end

      def remove_section(section)
        patch.children_of(section).each { |child| remove_section(child) }
        section.destroy!
      end

      def next_position(items)
        (items.map(&:position).max || -1) + 1
      end

      def insert_position
        items = patch.section_items(patch.parent)
        return next_position(items) if patch.relative_section.nil?

        position = patch.relative_section.position
        position += 1 if patch.placement == "after"

        # Sections and links share the visible order. Shift from the end to keep positions unique.
        items
          .select { |item| item.position >= position }
          .sort_by(&:position)
          .reverse_each { |item| item.update!(position: item.position + 1) }
        position
      end
    end
  end
end
