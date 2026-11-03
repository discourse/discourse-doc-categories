# frozen_string_literal: true

RSpec.describe SiteController do
  fab!(:admin)
  fab!(:group)
  fab!(:category)
  fab!(:public_subcategory) { Fabricate(:category, parent_category: category) }
  fab!(:private_subcategory) do
    Fabricate(:private_category, parent_category: category, group: group)
  end
  fab!(:public_topic) do
    Fabricate(:topic_with_op, category: public_subcategory, title: "Public subcategory guide")
  end
  fab!(:private_topic) do
    Fabricate(
      :topic_with_op,
      category: private_subcategory,
      title: "Confidential restricted subcategory guide",
    )
  end
  fab!(:index) { Fabricate(:doc_categories_index, category: category, index_topic_id: -1) }
  fab!(:section) do
    Fabricate(:doc_categories_sidebar_section, index: index, title: "Topics", auto_index: true)
  end
  fab!(:public_link) do
    Fabricate(
      :doc_categories_sidebar_link,
      sidebar_section: section,
      topic: public_topic,
      title: nil,
      href: public_topic.relative_url,
      position: 0,
    )
  end
  fab!(:private_link) do
    Fabricate(
      :doc_categories_sidebar_link,
      sidebar_section: section,
      topic: private_topic,
      title: "Restricted guide",
      href: private_topic.relative_url,
      position: 1,
      auto_indexed: true,
    )
  end

  before { SiteSetting.doc_categories_enabled = true }

  def serialized_links(category_id)
    serialized_category =
      response.parsed_body["categories"].find { |record| record["id"] == category_id }
    Array(serialized_category["doc_category_index"]).flat_map { |record| record["links"] }
  end

  def published_links(messages)
    serialized_category =
      messages
        .flat_map { |message| Array(message.data[:categories]) }
        .find { |record| record[:id] == category.id }
    expect(serialized_category).to be_present
    Array(serialized_category[:doc_category_index]).flat_map { |record| record["links"] }
  end

  describe "#site" do
    it "omits restricted cross-category links from the shared cache and public broadcasts" do
      get "/site.json"
      expect(response.status).to eq(200)
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])
      expect(response.body).not_to include(
        private_topic.title,
        private_link.title,
        private_link.href,
      )

      messages = MessageBus.track_publish("/categories") { category.publish_category }
      expect(published_links(messages).pluck("topic_id")).to eq([public_topic.id])
    end

    it "keeps a private category's own index available to its readers" do
      private_index =
        Fabricate(:doc_categories_index, category: private_subcategory, index_topic_id: -1)
      own_section =
        Fabricate(:doc_categories_sidebar_section, index: private_index, title: "Private docs")
      Fabricate(
        :doc_categories_sidebar_link,
        sidebar_section: own_section,
        topic: private_topic,
        title: nil,
        href: private_topic.relative_url,
      )
      Site.clear_cache
      Site.clear_anon_cache!

      get "/site.json"
      expect(response.parsed_body["categories"].pluck("id")).not_to include(private_subcategory.id)
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])

      user = Fabricate(:user)
      group.add(user)
      sign_in(user)
      get "/site.json"
      expect(serialized_links(private_subcategory.id).pluck("topic_id")).to eq([private_topic.id])
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])

      delete "/session/current.json"
      expect(response).to redirect_to("/")
      get "/site.json"
      expect(response.parsed_body["categories"].pluck("id")).not_to include(private_subcategory.id)
      expect(response.body).not_to include(private_topic.title)
    end

    it "refreshes cached and live links when a topic moves into and out of a private category" do
      get "/site.json"
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])

      messages =
        MessageBus.track_publish("/categories") do
          PostRevisor.new(public_topic.first_post).revise!(
            admin,
            category_id: private_subcategory.id,
          )
        end
      expect(published_links(messages)).to be_empty
      get "/site.json"
      expect(serialized_links(category.id)).to be_empty
      expect(public_link.reload.topic_id).to eq(public_topic.id)

      messages =
        MessageBus.track_publish("/categories") do
          PostRevisor.new(public_topic.reload.first_post).revise!(
            admin,
            category_id: public_subcategory.id,
          )
        end
      expect(published_links(messages).pluck("topic_id")).to eq([public_topic.id])
      get "/site.json"
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])
    end

    it "refreshes parent indexes when a subcategory becomes private or public" do
      get "/site.json"
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])

      messages =
        MessageBus.track_publish("/categories") do
          public_subcategory.set_permissions(group.name => :full)
          public_subcategory.save!
        end
      expect(published_links(messages)).to be_empty
      get "/site.json"
      expect(serialized_links(category.id)).to be_empty

      messages =
        MessageBus.track_publish("/categories") do
          public_subcategory.set_permissions(everyone: :full)
          public_subcategory.save!
        end
      expect(published_links(messages).pluck("topic_id")).to eq([public_topic.id])
      get "/site.json"
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])
    end

    it "removes cached and live links when a topic becomes a private message" do
      get "/site.json"
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])

      messages =
        MessageBus.track_publish("/categories") do
          public_topic.update!(archetype: Archetype.private_message, category_id: nil)
        end

      expect(published_links(messages)).to be_empty
      get "/site.json"
      expect(serialized_links(category.id)).to be_empty
      expect(response.body).not_to include(public_topic.title)
    end

    it "keeps private links unpublished when a move is rolled back" do
      get "/site.json"

      messages =
        MessageBus.track_publish("/categories") do
          Topic.transaction(requires_new: true) do
            private_topic.update!(category_id: public_subcategory.id)
            raise ActiveRecord::Rollback
          end
        end

      expect(messages).to be_empty
      get "/site.json"
      expect(serialized_links(category.id).pluck("topic_id")).to eq([public_topic.id])
      expect(response.body).not_to include(private_topic.title)
    end
  end
end
