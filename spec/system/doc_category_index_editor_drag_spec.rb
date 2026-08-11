# frozen_string_literal: true

# Characterization of the index editor's drag behaviour, written against the
# hand-rolled implementation so it can hold that behaviour still while the
# implementation is replaced by core's drag primitives. Nothing here names how a
# drag is wired: it drives real pointer input and asserts on the resulting order,
# so it is worth the same either side of that change.
#
# Real drags rather than synthetic events, deliberately. A synthetic sequence
# asserts that the handlers a test dispatches to are the handlers the browser
# would have reached, which is the one thing a rewrite of the event plumbing
# changes.
#
# Selectors are built with Playwright's `:has-text()` rather than a position: an
# index is exactly what a reorder changes, so a selector built from one would
# follow the row it was meant to pin.
describe "Doc Category Index Editor | dragging" do
  fab!(:admin)
  fab!(:category, :category_with_definition)

  let(:editor) { PageObjects::Components::DocIndexEditor.new }

  # Above and below the target's midpoint. Its centre is the ambiguous point and
  # resolves the same way every time, so a before/after drop has to aim off it.
  let(:above) { { x: 40, y: 4 } }
  let(:below) { { x: 40, y: 44 } }

  let(:first_link) { ".doc-category-index-editor__link:has-text('First')" }
  let(:second_link) { ".doc-category-index-editor__link:has-text('Second')" }

  # A row is the drop target, but only its grip is draggable, so a drag has to
  # be pressed there. Pressing the row instead starts nothing, and the drag then
  # fails silently: the order simply does not change, which any assertion that
  # the order stayed put would happily accept.
  let(:second_link_grip) { "#{second_link} .doc-category-index-editor__drag-handle" }
  let(:first_link_grip) { "#{first_link} .doc-category-index-editor__drag-handle" }

  let(:spare_section_body) do
    ".doc-category-index-editor__section:has-text('Spare') " \
      ".doc-category-index-editor__section-body"
  end

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

    it "reorders a link dropped above another" do
      expect(editor.link_labels).to eq(%w[First Second])

      drag_and_drop(source: second_link_grip, target: first_link, target_position: above)

      expect(editor).to have_link_order(%w[Second First])
    end

    # The mirror of the test above, through the other branch of the midpoint
    # check. Asserting instead that a drop below leaves the order alone would
    # pass just as well against a drag that never started, which is precisely how
    # a broken drag hides.
    it "reorders a link dropped below another" do
      drag_and_drop(source: first_link_grip, target: second_link, target_position: below)

      expect(editor).to have_link_order(%w[Second First])
    end

    it "keeps the reorder after applying" do
      drag_and_drop(source: second_link_grip, target: first_link, target_position: above)
      expect(editor).to have_link_order(%w[Second First])

      editor.click_apply

      expect(editor).to have_link_order(%w[Second First])
    end
  end

  context "with links in two sections" do
    before do
      editor.visit_doc_index_tab(category)
      editor.switch_to_mode("mode_direct")
      editor.add_section(title: "Guides")
      editor.add_manual_link(title: "First", url: "/first")
      editor.add_section(title: "Reference")
      editor.add_manual_link(title: "Second", url: "/second")
    end

    it "moves a link into another section" do
      drag_and_drop(source: second_link_grip, target: first_link, target_position: above)

      expect(editor).to have_link_order(%w[Second First])
      expect(editor.links_in_section("Reference")).to be_empty
      expect(editor.links_in_section("Guides")).to eq(%w[Second First])
    end

    it "reorders the sections themselves" do
      expect(editor.section_labels).to eq(%w[Guides Reference])

      # A section's own grip is a direct child of its ROW, a sibling of the
      # `__section` element rather than inside it. Descending from `__section`
      # therefore reaches only the grips of the links nested within, and drags a
      # link while looking like it drags a section, which fails as silently as a
      # drag that never started.
      drag_and_drop(
        source:
          ".doc-category-index-editor__section-row:has-text('Reference') > .doc-category-index-editor__drag-handle",
        target: ".doc-category-index-editor__section:has-text('Guides')",
        target_position: above,
      )

      expect(editor).to have_section_order(%w[Reference Guides])
    end
  end

  context "with an empty section" do
    before do
      editor.visit_doc_index_tab(category)
      editor.switch_to_mode("mode_direct")
      editor.add_section(title: "Guides")
      editor.add_manual_link(title: "First", url: "/first")
      editor.add_section(title: "Spare")
    end

    # The one case a link has no row to aim at. It lands IN the section rather
    # than beside one of its rows, which is why the body is a target of its own
    # resolving `inside`, nested in a row target that only takes sections.
    it "takes a link dropped into a section with no rows" do
      expect(editor.links_in_section("Spare")).to be_empty

      drag_and_drop(source: first_link_grip, target: spare_section_body)

      expect(editor).to have_link_order(%w[First])
      expect(editor.links_in_section("Spare")).to eq(%w[First])
      expect(editor.links_in_section("Guides")).to be_empty
    end
  end
end
