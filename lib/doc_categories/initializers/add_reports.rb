# frozen_string_literal: true

module ::DocCategories
  module Initializers
    class AddReports < Initializer
      def apply
        plugin.add_report("doc_categories_missing_topics") do |report|
          DocCategories::Reports::MissingTopicsReport.new(report).run
        end

        plugin.add_report("doc_categories_extraneous_items") do |report|
          DocCategories::Reports::ExtraneousItemsReport.new(report).run
        end
      end
    end
  end
end
