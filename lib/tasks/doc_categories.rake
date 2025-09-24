# frozen_string_literal: true

namespace :doc_categories do
  desc "Parse active doc index topics and populate sidebar sections/links"
  task build_sidebar: :environment do
    next if !SiteSetting.doc_categories_enabled

    DocCategories::Index
      .includes(:category)
      .find_each do |index|
        category = index.category
        puts "Processing category ##{category.id} - #{category.name}"
        DocCategories::IndexStructureRefresher.new(category.id).refresh!
        index.reload
        puts " ⮑  Created #{index.sidebar_sections.count} sections and #{index.sidebar_sections.sum { |section| section.sidebar_links.count }} links"
        puts ""
      rescue => e
        puts "Failed to process category ##{category.id}: #{e.message}"
      end
  end
end
