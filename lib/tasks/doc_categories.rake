# frozen_string_literal: true

namespace :doc_categories do
  desc "Parse active doc index topics and populate sidebar sections/links"
  task build_sidebar: :environment do
    next if !SiteSetting.doc_categories_enabled

    DocCategories::Index
      .includes(:category)
      .find_each do |index|
        category = index.category

        if category.blank?
          puts "Skipping index ##{index.id} because category #{index.category_id} is missing."
          next
        end

        puts "Processing category ##{category.id} (#{category.name})"
        DocCategories::IndexStructureRefresher.new(category.id).refresh!
      rescue => e
        puts "Failed to process category ##{category.id}: #{e.message}"
      end
  end
end
