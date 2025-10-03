# frozen_string_literal: true

describe PostRevisor do
  fab!(:doc_category, :category_with_definition)
  fab!(:regular_category, :category_with_definition)
  fab!(:doc_topic) { Fabricate(:topic_with_op, category: doc_category) }
  fab!(:regular_topic) { Fabricate(:topic_with_op, category: regular_category) }

  let!(:doc_index) do
    Fabricate(:doc_categories_index, category: doc_category, index_topic: doc_topic)
  end

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.editing_grace_period = 0

    doc_topic.update!(bumped_at: 1.day.ago)
    regular_topic.update!(bumped_at: 1.day.ago)
  end

  describe "topic bumping for doc categories" do
    it "bumps the topic when editing the OP in a doc category" do
      post = doc_topic.first_post
      revisor = PostRevisor.new(post)

      expect { revisor.revise!(post.user, raw: "#{post.raw}\nUpdated content") }.to change {
        post.topic.reload.bumped_at
      }
    end

    it "does not bump when editing a reply in a doc category" do
      reply_post = Fabricate(:post, topic: doc_topic)
      revisor = PostRevisor.new(reply_post)

      expect {
        revisor.revise!(reply_post.user, raw: "#{reply_post.raw}\nUpdated reply")
      }.not_to change { reply_post.topic.reload.bumped_at }
    end

    it "does not bump when editing the OP in a regular category" do
      post = regular_topic.first_post
      revisor = PostRevisor.new(post)

      expect { revisor.revise!(post.user, raw: "#{post.raw}\nUpdated content") }.not_to change {
        post.topic.reload.bumped_at
      }
    end

    it "does not bump when editing only the title in a doc category" do
      post = doc_topic.first_post
      revisor = PostRevisor.new(post)

      expect { revisor.revise!(post.user, title: "New Title") }.not_to change {
        post.topic.reload.bumped_at
      }
    end

    it "bumps when editing both raw and title in a doc category" do
      post = doc_topic.first_post
      revisor = PostRevisor.new(post)

      expect {
        revisor.revise!(post.user, raw: "#{post.raw}\nUpdated content", title: "New Title")
      }.to change { post.topic.reload.bumped_at }
    end
  end
end
