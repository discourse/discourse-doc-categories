# frozen_string_literal: true

# Batch mode's two cross-cutting behaviours: where a selection can be dropped,
# and what happens to a selection when the index underneath it is replaced.
#
# The populated section is seeded through the models rather than built through
# the UI. The editor's add-link flow reveals its controls on hover, so driving
# it makes the setup sensitive to whether the browser reports a fine pointer,
# which is not what any of these tests are about.
describe "Doc Category Index Editor | batch mode" do
  fab!(:admin)
  fab!(:category, :category_with_definition)

  fab!(:index) do
    Fabricate(
      :doc_categories_index,
      category: category,
      index_topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
    )
  end

  fab!(:guides) do
    Fabricate(:doc_categories_sidebar_section, index: index, title: "Guides", position: 0)
  end

  fab!(:first_link) do
    Fabricate(
      :doc_categories_sidebar_link,
      sidebar_section: guides,
      title: "First",
      href: "/first",
      position: 0,
    )
  end

  fab!(:second_link) do
    Fabricate(
      :doc_categories_sidebar_link,
      sidebar_section: guides,
      title: "Second",
      href: "/second",
      position: 1,
    )
  end

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  # Below the target row's midpoint, so the drop resolves to "after" rather
  # than onto the ambiguous centre.
  let(:below) { { x: 40, y: 44 } }

  before do
    SiteSetting.doc_categories_enabled = true
    SiteSetting.doc_categories_index_editor = true
    SiteSetting.enable_simplified_category_creation = true
    sign_in(admin)

    editor.visit_doc_index_tab(category)
    expect(editor).to have_editor
    expect(editor.link_labels).to eq(%w[First Second])
  end

  context "when dropping a selection into an empty section" do
    # A section with no links only ever exists as one the author just added:
    # the server drops an empty section from the index structure entirely.
    before do
      editor.add_trailing_section(title: "Spare")
      editor.toggle_batch_mode
      expect(editor).to have_batch_bar
    end

    # An empty section is the one destination with no row to aim at, so the
    # section itself has to stand as the target. Asserting on the links that
    # arrive rather than on the drop, because a drag onto a target that is not
    # there fails by changing nothing, which "the order stayed put" would
    # accept just as happily.
    it "moves every selected link into the section" do
      editor.select_link("First")
      editor.select_link("Second")
      expect(editor).to have_batch_selection_count(2)

      drag_and_drop(source: editor.batch_drag_handle, target: editor.section_body_selector("Spare"))

      expect(editor.links_in_section("Spare")).to eq(%w[First Second])
      expect(editor.links_in_section("Guides")).to be_empty
    end
  end

  context "when applying with a selection open" do
    before do
      editor.toggle_batch_mode
      expect(editor).to have_batch_bar
    end

    # Apply rebuilds every section and link from the server's response. A
    # selection held as references to the old objects survives that rebuild as
    # a count with nothing behind it: the rows all read as unselected while the
    # bar still claims a selection. Both halves are asserted, because either
    # one alone passes against the disagreement.
    #
    # The move is what leaves the index dirty, since Apply is only reachable
    # with pending changes. It is asserted on its own so that a regression
    # there cannot be mistaken for the selection bug below.
    it "leaves no selection behind in the bar or the rows" do
      editor.select_link("First")
      expect(editor).to have_batch_selection_count(1)
      expect(editor).to have_checked_link("First")

      drag_and_drop(
        source: editor.batch_drag_handle,
        target: editor.link_selector("Second"),
        target_position: below,
      )
      expect(editor).to have_link_order(%w[Second First])

      editor.click_apply
      expect(editor).to have_applied

      expect(editor).to have_unchecked_link("First")
      expect(editor).to have_no_batch_selection
    end
  end
end
