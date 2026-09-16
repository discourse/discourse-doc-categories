# frozen_string_literal: true

RSpec.describe DocCategories::IndexSaver do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:category_id) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:) }

    fab!(:category, :category_with_definition)

    let(:params) { { category_id: category.id, sections: sections_data } }
    let(:sections_data) { [{ title: "Intro", links: [{ title: "Link 1", href: "/t/slug/1" }] }] }

    before { SiteSetting.doc_categories_enabled = true }

    def build_sections(*sections)
      sections.map do |title, links|
        { title: title, links: links.map { |t, h| { title: t, href: h } } }
      end
    end

    context "when the contract is invalid" do
      let(:params) { { category_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context "when the category does not exist" do
      let(:params) { { category_id: -999, sections: [] } }

      it { is_expected.to fail_to_find_a_model(:category) }
    end

    context "when the index is in topic mode" do
      before do
        topic = Fabricate(:topic, category: category)
        Fabricate(:doc_categories_index, category: category, index_topic: topic)
      end

      it { is_expected.to fail_a_policy(:not_topic_managed) }
    end

    context "when force_direct converts topic mode to direct mode" do
      let(:params) { { category_id: category.id, sections: sections_data, force_direct: true } }

      before do
        topic = Fabricate(:topic, category: category)
        Fabricate(:doc_categories_index, category: category, index_topic: topic)
      end

      it { is_expected.to run_successfully }

      it "switches the index to direct mode" do
        result
        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.mode_direct?).to eq(true)
        expect(index.sidebar_sections.count).to eq(1)
      end
    end

    context "when sections are valid" do
      it { is_expected.to run_successfully }

      it "creates an index in direct mode with sections and links" do
        result
        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index).to be_present
        expect(index.mode_direct?).to eq(true)
        expect(index.sidebar_sections.count).to eq(1)
        expect(index.sidebar_sections.first.title).to eq("Intro")
        expect(index.sidebar_sections.first.sidebar_links.first.href).to eq("/t/slug/1")
      end

      it "replaces existing sections on subsequent saves" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: build_sections(["Old", [%w[A /a]]]),
          },
        )
        described_class.call(
          params: {
            category_id: category.id,
            sections: build_sections(["New", [%w[B /b]]]),
          },
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(1)
        expect(index.sidebar_sections.first.title).to eq("New")
      end

      it "returns the index structure in the response" do
        expect(result[:index_structure]).to be_present
      end
    end

    context "when sections_data is blank" do
      let(:sections_data) { [] }

      it { is_expected.to run_successfully }

      it "destroys the index" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: build_sections(["S", [%w[L /l]]]),
          },
        )
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

        described_class.call(params: { category_id: category.id, sections: [] })
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "does not destroy a topic-mode index" do
        topic = Fabricate(:topic, category: category)
        Fabricate(:doc_categories_index, category: category, index_topic: topic)

        # Topic mode blocks the policy, so this fails — index untouched
        result = described_class.call(params: { category_id: category.id, sections: [] })
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_present
      end
    end

    context "when sections is a Hash instead of an Array" do
      let(:sections_data) { { title: "Not an array" } }

      it "does not create an index" do
        result
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end
    end

    context "with limits" do
      it "fails when sections exceed MAX_SECTIONS" do
        sections =
          (DocCategories::IndexSaver::MAX_SECTIONS + 1).times.map do |i|
            { title: "Section #{i}", links: [{ title: "Link", href: "/t/s/#{i}" }] }
          end

        result = described_class.call(params: { category_id: category.id, sections: sections })
        expect(result).to fail_a_step(:parse_and_validate_sections)
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "fails when links in a section exceed MAX_LINKS_PER_SECTION" do
        links =
          (DocCategories::IndexSaver::MAX_LINKS_PER_SECTION + 1).times.map do |i|
            { title: "Link #{i}", href: "/t/s/#{i}" }
          end

        result =
          described_class.call(
            params: {
              category_id: category.id,
              sections: [{ title: "Big", links: links }],
            },
          )
        expect(result).to fail_a_step(:parse_and_validate_sections)
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "allows exactly MAX_SECTIONS sections" do
        sections =
          DocCategories::IndexSaver::MAX_SECTIONS.times.map do |i|
            { title: "Section #{i}", links: [{ title: "Link", href: "/t/s/#{i}" }] }
          end

        result = described_class.call(params: { category_id: category.id, sections: sections })
        expect(result).to run_successfully

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(DocCategories::IndexSaver::MAX_SECTIONS)
      end
    end

    context "with filtering" do
      it "allows the first section to have a blank title" do
        sections = [
          { title: "", links: [{ title: "L", href: "/a" }] },
          { title: "Second", links: [{ title: "L", href: "/b" }] },
        ]

        described_class.call(params: { category_id: category.id, sections: sections })

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(2)
        expect(index.sidebar_sections.first.title).to eq("")
        expect(index.sidebar_sections.second.title).to eq("Second")
      end

      it "skips non-first sections with blank titles" do
        sections = [
          { title: "First", links: [{ title: "L", href: "/a" }] },
          { title: "", links: [{ title: "L", href: "/b" }] },
        ]

        described_class.call(params: { category_id: category.id, sections: sections })

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(1)
        expect(index.sidebar_sections.first.title).to eq("First")
      end

      it "skips links with blank hrefs" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ title: "S", links: [{ title: "No URL", href: "" }] }],
          },
        )

        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "skips links with no title and no topic_id" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ title: "S", links: [{ title: "", href: "https://external.com" }] }],
          },
        )

        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "destroys an existing index when all sections are filtered out" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: build_sections(["S", [%w[L /l]]]),
          },
        )
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ title: "S", links: [{ title: "", href: "" }] }],
          },
        )

        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end
    end

    context "with topic links" do
      fab!(:topic) { Fabricate(:topic, category: category, title: "My topic title for testing") }

      it "extracts topic_id from href URLs" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              { title: "S", links: [{ title: "Custom", href: "/t/#{topic.slug}/#{topic.id}" }] },
            ],
          },
        )

        link =
          DocCategories::Index
            .find_by(category_id: category.id)
            .sidebar_sections
            .first
            .sidebar_links
            .first
        expect(link.topic_id).to eq(topic.id)
      end

      it "uses explicit topic_id when provided" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              {
                title: "S",
                links: [{ title: "Custom", href: "/t/whatever/999", topic_id: topic.id }],
              },
            ],
          },
        )

        link =
          DocCategories::Index
            .find_by(category_id: category.id)
            .sidebar_sections
            .first
            .sidebar_links
            .first
        expect(link.topic_id).to eq(topic.id)
      end

      it "stores nil title when it matches the topic title (auto title)" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              {
                title: "S",
                links: [
                  { title: topic.title, href: "/t/#{topic.slug}/#{topic.id}", topic_id: topic.id },
                ],
              },
            ],
          },
        )

        link =
          DocCategories::Index
            .find_by(category_id: category.id)
            .sidebar_sections
            .first
            .sidebar_links
            .first
        expect(link.title).to be_nil
      end

      it "preserves custom title when it differs from the topic title" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              {
                title: "S",
                links: [
                  {
                    title: "Custom Name",
                    href: "/t/#{topic.slug}/#{topic.id}",
                    topic_id: topic.id,
                  },
                ],
              },
            ],
          },
        )

        link =
          DocCategories::Index
            .find_by(category_id: category.id)
            .sidebar_sections
            .first
            .sidebar_links
            .first
        expect(link.title).to eq("Custom Name")
      end
    end

    it "saves icon on links" do
      described_class.call(
        params: {
          category_id: category.id,
          sections: [{ title: "S", links: [{ title: "L", href: "/a", icon: "book" }] }],
        },
      )

      link =
        DocCategories::Index
          .find_by(category_id: category.id)
          .sidebar_sections
          .first
          .sidebar_links
          .first
      expect(link.icon).to eq("book")
    end

    context "with auto-index sections" do
      it "allows an auto-index section with no manual links" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ title: "Auto", auto_index: true, links: [] }],
          },
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index).to be_present
        section = index.sidebar_sections.first
        expect(section.title).to eq("Auto")
        expect(section.auto_index).to eq(true)
      end

      it "still skips non-auto-index sections with empty links" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              { title: "Empty", links: [] },
              { title: "Auto", auto_index: true, links: [] },
            ],
          },
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(1)
        expect(index.sidebar_sections.first.title).to eq("Auto")
      end

      it "preserves auto_indexed flag on links through save cycle" do
        topic = Fabricate(:topic, category: category)

        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              {
                title: "Auto",
                auto_index: true,
                links: [{ title: "T", href: topic.relative_url, topic_id: topic.id }],
              },
            ],
          },
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        link = index.sidebar_sections.first.sidebar_links.first
        link.update!(auto_indexed: true)

        described_class.call(
          params: {
            category_id: category.id,
            sections: [
              {
                title: "Auto",
                auto_index: true,
                links: [{ title: "T", href: topic.relative_url, topic_id: topic.id }],
              },
            ],
          },
        )

        index.reload
        link = index.sidebar_sections.first.sidebar_links.first
        expect(link.auto_indexed).to eq(true)
      end

      it "does not mark links as auto_indexed if they were not previously" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ title: "S", links: [{ title: "L", href: "/t/slug/1", topic_id: 1 }] }],
          },
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        link = index.sidebar_sections.first.sidebar_links.first
        expect(link.auto_indexed).to eq(false)
      end
    end

    context "with auto-index sync" do
      fab!(:topic) { Fabricate(:topic, category: category) }
      fab!(:post) { Fabricate(:post, topic: topic) }

      let!(:index) do
        DocCategories::Index.create!(
          category: category,
          index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
        )
      end
      let!(:auto_section) do
        DocCategories::SidebarSection.create!(
          index: index,
          title: "Topics",
          position: 0,
          auto_index: true,
        )
      end

      it "syncs when force_sync is true even if section id is preserved" do
        described_class.call(
          params: {
            category_id: category.id,
            force_sync: true,
            sections: [{ id: auto_section.id, title: "Topics", auto_index: true, links: [] }],
          },
        )

        index.reload
        expect(index.auto_index_section.sidebar_links.auto_indexed.pluck(:topic_id)).to include(
          topic.id,
        )
      end

      it "does not sync when section id is preserved and force is false" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ id: auto_section.id, title: "Topics", auto_index: true, links: [] }],
          },
        )

        index.reload
        expect(index.auto_index_section.sidebar_links.auto_indexed.count).to eq(0)
      end

      it "syncs when section id is nil (new section)" do
        described_class.call(
          params: {
            category_id: category.id,
            sections: [{ title: "Topics", auto_index: true, links: [] }],
          },
        )

        index.reload
        expect(index.auto_index_section.sidebar_links.auto_indexed.pluck(:topic_id)).to include(
          topic.id,
        )
      end

      it "does not sync when there is no auto-index section" do
        auto_section.update!(auto_index: false)

        result =
          described_class.call(
            params: {
              category_id: category.id,
              force_sync: true,
              sections: [
                {
                  id: auto_section.id,
                  title: "Topics",
                  auto_index: false,
                  links: [{ title: "Manual", href: "/t/slug/1" }],
                },
              ],
            },
          )

        expect(result).to run_successfully
        index.reload
        expect(index.sidebar_sections.first.sidebar_links.auto_indexed.count).to eq(0)
      end
    end
  end
end
