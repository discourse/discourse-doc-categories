# frozen_string_literal: true

module PageObjects
  module Components
    class DocCategorySettings < Base
      def has_index_topic_chooser?
        has_css?(".doc-categories-settings .topic-chooser")
      end

      def has_no_index_topic_chooser?
        has_no_css?(".doc-categories-settings .topic-chooser")
      end

      def has_index_topic?(topic)
        has_css?(".doc-categories-settings .selected-name", text: topic.title)
      end

      def has_no_index_topic?
        has_css?(".doc-categories-settings .topic-chooser:not(.has-selection)")
      end

      def has_editor_tab?
        has_css?(".edit-category-doc-index")
      end

      def has_no_editor_tab?
        has_no_css?(".edit-category-doc-index")
      end

      def select_index_topic(topic)
        chooser = SelectKit.new(".doc-categories-settings .topic-chooser")
        chooser.expand
        chooser.search(topic.id)
        chooser.select_row_by_value(topic.id)
      end

      def clear_index_topic
        find(".doc-categories-settings .btn-clear").click
      end

      def change_featured_topic_count(count)
        fill_in("num_featured_topics", with: count)
      end
    end
  end
end
