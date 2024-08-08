# frozen_string_literal: true

RSpec.describe Search do
  describe "in:docs" do
    fab!(:admin) { Fabricate(:admin, refresh_auto_groups: true) }
    fab!(:category) { Fabricate(:category_with_definition) }
    fab!(:topic) { Fabricate(:topic, category: category, title: "looking for this?") }
    fab!(:post) { Fabricate(:post, topic: topic, post_number: 1) }
    fab!(:documentation_category) { Fabricate(:category_with_definition) }
    fab!(:documentation_category_index_topic) do
      Fabricate(:topic, category: documentation_category)
    end
    fab!(:documentation_category_topic) do
      Fabricate(:topic, category: documentation_category, title: "looking for this in the docs?")
    end
    fab!(:documentation_category_post) do
      Fabricate(:post, topic: documentation_category_topic, post_number: 1)
    end
    fab!(:documentation_subcategory) do
      Fabricate(:category_with_definition, parent_category_id: documentation_category.id)
    end
    fab!(:documentation_subcategory_topic) do
      Fabricate(
        :topic,
        category: documentation_subcategory,
        title: "looking for this in the docs subcategory?",
      )
    end
    fab!(:documentation_subcategory_post) do
      Fabricate(:post, topic: documentation_subcategory_topic, post_number: 1)
    end

    before do
      SearchIndexer.enable
      Jobs.run_immediately!

      [topic, documentation_category_topic, documentation_subcategory_topic].each do |t|
        SearchIndexer.index(t, force: true)
      end

      documentation_category.custom_fields[
        DocCategories::CATEGORY_INDEX_TOPIC
      ] = documentation_category_topic.id
      documentation_category.save!
    end

    context "when the plugin is enabled" do
      before { SiteSetting.doc_categories_enabled = true }

      it "includes only posts from the doc categories (including subcategories) in the results" do
        results_with_advanced_search_trigger =
          Search.execute("looking in:docs", guardian: Guardian.new(admin)).posts.map(&:id)
        results_without_advanced_search_trigger =
          Search.execute("looking", guardian: Guardian.new(admin)).posts.map(&:id)

        expect(results_with_advanced_search_trigger).to contain_exactly(
          documentation_category_post.id,
          documentation_subcategory_post.id,
        )
        expect(results_with_advanced_search_trigger).not_to match_array(
          results_without_advanced_search_trigger,
        )
        expect(results_without_advanced_search_trigger).to include(
          *results_with_advanced_search_trigger,
        )
      end
    end

    context "when the plugin is disabled" do
      before { SiteSetting.doc_categories_enabled = false }

      it "won't modify the search results" do
        results_with_advanced_search_trigger =
          Search.execute("looking in:docs", guardian: Guardian.new(admin)).posts.map(&:id)
        results_without_advanced_search_trigger =
          Search.execute("looking", guardian: Guardian.new(admin)).posts.map(&:id)

        expect(results_without_advanced_search_trigger).to contain_exactly(
          post.id,
          documentation_category_post.id,
          documentation_subcategory_post.id,
        )
        expect(results_with_advanced_search_trigger).to match_array(
          results_without_advanced_search_trigger,
        )
      end
    end
  end
end
