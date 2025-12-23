# frozen_string_literal: true

describe DocCategories::IndexStructureRefresher do
  fab!(:documentation_category, :category_with_definition)
  fab!(:other_category, :category_with_definition)

  fab!(:doc_topic) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:doc_topic_two) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:doc_topic_bare_url) { Fabricate(:topic_with_op, category: documentation_category) }
  fab!(:other_category_topic) { Fabricate(:topic_with_op, category: other_category) }
  fab!(:invisible_topic) do
    Fabricate(:topic_with_op, category: documentation_category, visible: false)
  end
  fab!(:index_topic) do
    Fabricate(:topic_with_op, category: documentation_category).tap do |topic|
      topic.first_post.update!(raw: <<~MD)
          ## Docs Section
          * [#{doc_topic.title}](/t/#{doc_topic.slug}/#{doc_topic.id})
          * #{doc_topic_two.slug}: [#{doc_topic_two.title}](/t/#{doc_topic_two.slug}/#{doc_topic_two.id})
          * [#{other_category_topic.title}](/t/#{other_category_topic.slug}/#{other_category_topic.id})
          * [#{invisible_topic.title}](/t/#{invisible_topic.slug}/#{invisible_topic.id})
          * #{Discourse.base_url}/t/#{doc_topic_bare_url.slug}/#{doc_topic_bare_url.id}
          * [External](https://example.com/docs)
          * No link here
        MD
      topic.first_post.rebake!
    end
  end

  fab!(:doc_index) do
    Fabricate(:doc_categories_index, category: documentation_category, index_topic: index_topic)
  end

  let(:refresher) { described_class.new(documentation_category.id) }

  before { SiteSetting.doc_categories_enabled = true }

  def sidebar_sections
    DocCategories::SidebarSection
      .joins(:index)
      .where(doc_categories_indexes: { category_id: documentation_category.id })
      .includes(:sidebar_links)
      .order(:position)
  end

  describe "#refresh!" do
    it "rebuilds the sidebar structure from the index topic" do
      doc_index
        .sidebar_sections
        .create!(position: 9, title: "Stale")
        .tap do |section|
          section.sidebar_links.create!(position: 4, title: "Old", href: "/outdated")
        end

      refresher.refresh!

      sections = sidebar_sections
      expect(sections.length).to eq(1)

      section = sections.first
      expect(section.title).to eq("Docs Section")
      expect(section.position).to eq(0)

      expect(
        section.sidebar_links.map { |link| [link.position, link.href, link.title, link.topic_id] },
      ).to eq(
        [
          [0, "/t/#{doc_topic.slug}/#{doc_topic.id}", doc_topic.title, doc_topic.id],
          [1, "/t/#{doc_topic_two.slug}/#{doc_topic_two.id}", doc_topic_two.slug, doc_topic_two.id],
          [
            2,
            "/t/#{other_category_topic.slug}/#{other_category_topic.id}",
            other_category_topic.title,
            other_category_topic.id,
          ],
          [
            3,
            "/t/#{invisible_topic.slug}/#{invisible_topic.id}",
            invisible_topic.title,
            invisible_topic.id,
          ],
          [
            4,
            "#{Discourse.base_url}/t/#{doc_topic_bare_url.slug}/#{doc_topic_bare_url.id}",
            doc_topic_bare_url.title,
            doc_topic_bare_url.id,
          ],
          [5, "https://example.com/docs", "External", nil],
        ],
      )
    end

    it "removes existing sidebar data when no valid links remain" do
      doc_index
        .sidebar_sections
        .create!(position: 0, title: "Old")
        .tap do |section|
          section.sidebar_links.create!(position: 0, title: "Old link", href: "/old")
        end

      index_topic.first_post.update!(raw: <<~MD)
          ## Empty Section
          * No link here
        MD
      index_topic.first_post.rebake!

      allow(Site).to receive(:clear_cache)

      messages = MessageBus.track_publish("/categories") { refresher.refresh! }

      expect(sidebar_sections).to be_empty
      expect(Site).to have_received(:clear_cache)
      category_ids =
        messages.flat_map { |message| Array(message.data[:categories]).map { |c| c[:id] } }
      expect(category_ids).to include(documentation_category.id)
    end

    it "destroys the index and publishes changes when the topic leaves the category" do
      allow(Site).to receive(:clear_cache)

      index_topic.update!(category: other_category)

      messages = MessageBus.track_publish("/categories") { refresher.refresh! }

      expect(DocCategories::Index.exists?(category_id: documentation_category.id)).to eq(false)
      expect(Site).to have_received(:clear_cache)
      category_ids =
        messages.flat_map { |message| Array(message.data[:categories]).map { |c| c[:id] } }
      expect(category_ids).to include(documentation_category.id)
    end

    it "returns without side effects when no index exists" do
      doc_index.destroy!
      allow(Site).to receive(:clear_cache)

      expect { refresher.refresh! }.not_to change { DocCategories::SidebarSection.count }
      expect(Site).not_to have_received(:clear_cache)
    end
  end
end
