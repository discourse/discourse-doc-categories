# frozen_string_literal: true

# The keyboard path to reordering. A drag is unreachable by keyboard, so without
# it the editor's only route to an order has no keyboard route at all, and that
# is what these specs pin: the outcomes, not the wiring.
#
# A move is the shared list's two steps — open the row's handle menu, choose a
# destination — and rows are addressed through the accessible name of their
# handle, which is what a screen reader user navigates by. A selector built from
# a row's position would follow whichever row moved into it, which is precisely
# what a reorder changes.
describe "Doc Category Index Editor | keyboard reordering" do
  fab!(:admin)
  fab!(:category, :category_with_definition)

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)
  end

  context "with two links in one section" do
    before do
      editor.visit_doc_index_tab(category)
      editor.switch_to_mode("mode_direct")
      editor.add_section(title: "Guides")
      editor.add_manual_link(title: "First", url: "/first")
      editor.add_manual_link(title: "Second", url: "/second")
    end

    it "moves a link down" do
      expect(editor.link_labels).to eq(%w[First Second])

      editor.move_link("First", :down)

      expect(editor).to have_link_order(%w[Second First])
    end

    it "moves a link back up" do
      editor.move_link("Second", :up)

      expect(editor).to have_link_order(%w[Second First])
    end

    it "offers only the destinations a row can actually reach" do
      # Omitted rather than shown-and-disabled: a menu holding an unavailable
      # destination counts it in the set it publishes, so a reader is told there
      # are four choices while the cursor can land on two.
      expect(editor).to have_link_move_disabled("First", :up)
      expect(editor).to have_link_move_disabled("Second", :down)
      expect(editor).to have_link_move_available("First", :down)
      expect(editor).to have_link_move_available("Second", :up)
    end
  end

  context "with links across two sections" do
    before do
      editor.visit_doc_index_tab(category)
      editor.switch_to_mode("mode_direct")
      editor.add_section(title: "Guides")
      editor.add_manual_link(title: "First", url: "/first")
      editor.add_section(title: "Reference")
      editor.add_manual_link(title: "Second", url: "/second")
    end

    # A step past the end of a section carries the link into the next one rather
    # than stopping: the sections read as one continuous index, so an internal
    # edge is an artefact of how it is built and not anything the reader sees.
    it "carries a link into the section below" do
      expect(editor.links_in_section("Guides")).to eq(%w[First])

      editor.move_link("First", :down)

      expect(editor).to have_link_order(%w[First Second])
      expect(editor.links_in_section("Guides")).to be_empty
      expect(editor.links_in_section("Reference")).to eq(%w[First Second])
    end

    it "carries a link into the section above" do
      editor.move_link("Second", :up)

      expect(editor).to have_link_order(%w[First Second])
      expect(editor.links_in_section("Guides")).to eq(%w[First Second])
      expect(editor.links_in_section("Reference")).to be_empty
    end

    it "keeps focus on the handle after crossing into another section" do
      # Without this the row is rebuilt in the other section and focus lands on
      # the body, so a second press is impossible and the path stops being a
      # keyboard path after one step.
      editor.move_link("First", :down)

      expect(editor).to have_focused_move_button("First", :down)
    end

    it "keeps focus when crossing upwards too" do
      editor.move_link("Second", :up)

      expect(editor).to have_focused_move_button("Second", :up)
    end

    it "only runs out of moves at the ends of the whole index" do
      # The first link of the second section can still go up, because up means
      # the section above rather than the top of this one.
      expect(editor).to have_link_move_available("Second", :up)
      expect(editor).to have_link_move_disabled("First", :up)
      expect(editor).to have_link_move_disabled("Second", :down)
    end

    it "sends a link to a named section from the menu" do
      # The deliberate way across, beside the step that spills into whichever
      # section happens to be adjacent. It appends, since the reader named a
      # destination rather than a direction.
      editor.move_link_to_section("First", "Reference")

      expect(editor.links_in_section("Guides")).to be_empty
      expect(editor.links_in_section("Reference")).to eq(%w[Second First])
    end

    it "reorders the sections themselves" do
      expect(editor).to have_section_order(%w[Guides Reference])

      editor.move_section("Guides", :down)

      expect(editor).to have_section_order(%w[Reference Guides])
    end

    it "keeps a moved link with its section" do
      editor.move_section("Reference", :up)

      expect(editor).to have_section_order(%w[Reference Guides])
      expect(editor.links_in_section("Reference")).to eq(%w[Second])
      expect(editor.links_in_section("Guides")).to eq(%w[First])
    end
  end
end
