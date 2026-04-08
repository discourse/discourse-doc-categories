# frozen_string_literal: true

RSpec.describe DocCategories::IndexSaver do
  fab!(:category, :category_with_definition)

  subject(:saver) { described_class.new(category) }

  def build_sections(*sections)
    sections.map do |title, links|
      { title: title, links: links.map { |t, h| { title: t, href: h } } }
    end
  end

  describe "#save_sections!" do
    it "raises when sections_data is not an array" do
      expect { saver.save_sections!({ title: "not an array" }) }.to raise_error(
        Discourse::InvalidParameters,
      )
    end

    it "creates an index in direct mode with sections and links" do
      saver.save_sections!(build_sections(["Intro", [["Link 1", "/t/slug/1"]]]))

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index).to be_present
      expect(index.mode_direct?).to eq(true)
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("Intro")
      expect(index.sidebar_sections.first.sidebar_links.first.href).to eq("/t/slug/1")
    end

    it "replaces existing sections on subsequent saves" do
      saver.save_sections!(build_sections(["Old", [%w[A /a]]]))
      saver.save_sections!(build_sections(["New", [%w[B /b]]]))

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.sidebar_sections.count).to eq(1)
      expect(index.sidebar_sections.first.title).to eq("New")
    end

    it "destroys the index when sections_data is blank" do
      saver.save_sections!(build_sections(["S", [%w[L /l]]]))
      expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

      saver.save_sections!([])

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
    end

    it "does not destroy a topic-mode index when sections_data is blank" do
      topic = Fabricate(:topic, category: category)
      Fabricate(:doc_categories_index, category: category, index_topic: topic)

      saver.save_sections!([])

      expect(DocCategories::Index.find_by(category_id: category.id)).to be_present
    end

    it "raises when trying to overwrite a topic-mode index" do
      topic = Fabricate(:topic, category: category)
      Fabricate(:doc_categories_index, category: category, index_topic: topic)

      expect { saver.save_sections!(build_sections(["New", [%w[L /l]]])) }.to raise_error(
        Discourse::InvalidAccess,
      )

      index = DocCategories::Index.find_by(category_id: category.id)
      expect(index.mode_topic?).to eq(true)
      expect(index.sidebar_sections.count).to eq(0)
    end

    context "with limits" do
      it "raises when sections exceed MAX_SECTIONS" do
        sections =
          (described_class::MAX_SECTIONS + 1).times.map do |i|
            { title: "Section #{i}", links: [{ title: "Link", href: "/t/s/#{i}" }] }
          end

        expect { saver.save_sections!(sections) }.to raise_error(Discourse::InvalidParameters)
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "raises when links in a section exceed MAX_LINKS_PER_SECTION" do
        links =
          (described_class::MAX_LINKS_PER_SECTION + 1).times.map do |i|
            { title: "Link #{i}", href: "/t/s/#{i}" }
          end

        expect { saver.save_sections!([{ title: "Big", links: links }]) }.to raise_error(
          Discourse::InvalidParameters,
        )
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "allows exactly MAX_SECTIONS sections" do
        sections =
          described_class::MAX_SECTIONS.times.map do |i|
            { title: "Section #{i}", links: [{ title: "Link", href: "/t/s/#{i}" }] }
          end

        saver.save_sections!(sections)

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(described_class::MAX_SECTIONS)
      end
    end

    context "with filtering" do
      it "allows the first section to have a blank title" do
        saver.save_sections!(
          [
            { title: "", links: [{ title: "L", href: "/a" }] },
            { title: "Second", links: [{ title: "L", href: "/b" }] },
          ],
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(2)
        expect(index.sidebar_sections.first.title).to eq("")
        expect(index.sidebar_sections.second.title).to eq("Second")
      end

      it "skips non-first sections with blank titles" do
        saver.save_sections!(
          [
            { title: "First", links: [{ title: "L", href: "/a" }] },
            { title: "", links: [{ title: "L", href: "/b" }] },
          ],
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(1)
        expect(index.sidebar_sections.first.title).to eq("First")
      end

      it "skips links with blank hrefs" do
        saver.save_sections!([{ title: "S", links: [{ title: "No URL", href: "" }] }])

        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "skips links with no title and no topic_id" do
        saver.save_sections!([{ title: "S", links: [{ title: "", href: "https://external.com" }] }])

        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end

      it "destroys an existing index when all sections are filtered out" do
        saver.save_sections!(build_sections(["S", [%w[L /l]]]))
        expect(DocCategories::Index.find_by(category_id: category.id)).to be_present

        # Only links with blank hrefs and no topic_id are filtered, so use that to trigger filtering
        saver.save_sections!([{ title: "S", links: [{ title: "", href: "" }] }])

        expect(DocCategories::Index.find_by(category_id: category.id)).to be_nil
      end
    end

    context "with topic links" do
      fab!(:topic) { Fabricate(:topic, category: category, title: "My topic title for testing") }

      it "extracts topic_id from href URLs" do
        saver.save_sections!(
          [{ title: "S", links: [{ title: "Custom", href: "/t/#{topic.slug}/#{topic.id}" }] }],
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
        saver.save_sections!(
          [
            {
              title: "S",
              links: [{ title: "Custom", href: "/t/whatever/999", topic_id: topic.id }],
            },
          ],
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
        saver.save_sections!(
          [
            {
              title: "S",
              links: [
                { title: topic.title, href: "/t/#{topic.slug}/#{topic.id}", topic_id: topic.id },
              ],
            },
          ],
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
        saver.save_sections!(
          [
            {
              title: "S",
              links: [
                { title: "Custom Name", href: "/t/#{topic.slug}/#{topic.id}", topic_id: topic.id },
              ],
            },
          ],
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
      saver.save_sections!([{ title: "S", links: [{ title: "L", href: "/a", icon: "book" }] }])

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
      it "allows an empty auto-index section" do
        saver.save_sections!([{ title: "Auto", auto_index: true, links: [] }])

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index).to be_present
        section = index.sidebar_sections.first
        expect(section.title).to eq("Auto")
        expect(section.auto_index).to eq(true)
        expect(section.sidebar_links.count).to eq(0)
      end

      it "still skips non-auto-index sections with empty links" do
        saver.save_sections!(
          [{ title: "Empty", links: [] }, { title: "Auto", auto_index: true, links: [] }],
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        expect(index.sidebar_sections.count).to eq(1)
        expect(index.sidebar_sections.first.title).to eq("Auto")
      end

      it "preserves auto_indexed flag on links through save cycle" do
        topic = Fabricate(:topic, category: category)

        saver.save_sections!(
          [
            {
              title: "Auto",
              auto_index: true,
              links: [{ title: "T", href: topic.relative_url, topic_id: topic.id }],
            },
          ],
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        link = index.sidebar_sections.first.sidebar_links.first
        link.update!(auto_indexed: true)

        saver.save_sections!(
          [
            {
              title: "Auto",
              auto_index: true,
              links: [{ title: "T", href: topic.relative_url, topic_id: topic.id }],
            },
          ],
        )

        index.reload
        link = index.sidebar_sections.first.sidebar_links.first
        expect(link.auto_indexed).to eq(true)
      end

      it "does not mark links as auto_indexed if they were not previously" do
        saver.save_sections!(
          [{ title: "S", links: [{ title: "L", href: "/t/slug/1", topic_id: 1 }] }],
        )

        index = DocCategories::Index.find_by(category_id: category.id)
        link = index.sidebar_sections.first.sidebar_links.first
        expect(link.auto_indexed).to eq(false)
      end
    end
  end
end
