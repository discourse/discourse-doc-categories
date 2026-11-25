# frozen_string_literal: true

module DocCategories
  class IndexPatcher
    class Patch
      class Invalid < StandardError
      end

      attr_reader :category, :index, :section, :parent, :relative_section, :topics, :links
      delegate :operation, :placement, to: :@params

      def initialize(category:, index:, params:)
        @category = category
        @index = index
        @params = params
      end

      def prepare!
        @sections = index ? index.sidebar_sections.to_a : []
        @sections_by_parent = @sections.group_by(&:parent_section_id)

        case operation
        when "add_section"
          prepare_new_section
        when "move_section"
          prepare_section_move
        when "add_topic_links"
          @section = find_section(@params.section_id)
          @topics = topics_to_append
        when "remove_section"
          @section = find_section(@params.section_id)
        when "remove_topic_link"
          @section = find_section(@params.section_id)
          @links = section.sidebar_links.where(topic_id: @params.topic_id).to_a
          reject_patch("index_topic_link_not_found") if links.empty?
        end

        self
      end

      def title
        @params.title.strip
      end

      def children_of(section)
        @sections_by_parent.fetch(section&.id, [])
      end

      def section_items(parent)
        children_of(parent) + (parent ? parent.sidebar_links.to_a : [])
      end

      private

      def prepare_new_section
        if @sections.size >= Index::MAX_SECTIONS
          reject_patch("too_many_sections", max: Index::MAX_SECTIONS)
        end

        @parent, @relative_section = destination
        validate_destination(subtree_depth: 1)
        @topics = eligible_topics
      end

      def prepare_section_move
        @section = find_section(@params.section_id)
        @parent, @relative_section = destination
        if relative_section == section || ancestors(parent).include?(section)
          reject_patch("invalid_section_move")
        end
        reject_patch("auto_index_section_must_be_at_root") if parent && section.auto_index?

        validate_destination(subtree_depth: subtree_depth(section))
      end

      def topics_to_append
        topics = eligible_topics
        links = section.sidebar_links
        existing_ids = links.where(topic_id: topics.map(&:id)).pluck(:topic_id)
        new_topics = topics.reject { |topic| existing_ids.include?(topic.id) }
        if links.count + new_topics.size > Index::MAX_LINKS_PER_SECTION
          reject_patch("too_many_links", max: Index::MAX_LINKS_PER_SECTION)
        end
        new_topics
      end

      def find_section(section_id)
        @sections.find { |section| section.id == section_id } ||
          reject_patch("index_section_not_found")
      end

      def destination
        return nil, nil if @params.relative_section_id.nil?

        relative_section = find_section(@params.relative_section_id)
        return relative_section, nil if placement == "inside"

        [relative_section.parent_section, relative_section]
      end

      def validate_destination(subtree_depth:)
        reject_patch("auto_index_section_cannot_have_subsections") if parent&.auto_index?
        if ancestors(parent).size + subtree_depth > Index::MAX_SECTION_DEPTH
          reject_patch("section_depth_limit", max: Index::MAX_SECTION_DEPTH)
        end
      end

      def ancestors(section)
        ancestors = []
        while section
          ancestors << section
          section = section.parent_section
        end
        ancestors
      end

      def subtree_depth(section)
        1 + (children_of(section).map { |child| subtree_depth(child) }.max || 0)
      end

      def eligible_topics
        topic_ids = Array(@params.topic_ids)
        topics = ::Topic.where(id: topic_ids, visible: true).includes(:category).index_by(&:id)
        topic_ids.map do |topic_id|
          topic = topics[topic_id]
          if topic.nil? || !TopicEligibility.allowed?(topic, category_id: category.id)
            reject_patch("index_topic_unavailable")
          end
          topic
        end
      end

      def reject_patch(error, **args)
        raise Invalid, I18n.t("doc_categories.errors.#{error}", **args)
      end
    end
  end
end
