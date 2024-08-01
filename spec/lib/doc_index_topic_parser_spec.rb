# frozen_string_literal: true

RSpec.describe ::DocCategories::DocIndexTopicParser do
  let(:cooked_text) { <<-HTML }
      <ul>
        <li>Test: <a href="/test">This is a test</a></li>
      </ul>
    HTML

  context "when parsing sections" do
    it "extracts the index structure from HTML fragments containing a single list to a section without text" do
      cooked_text = <<-HTML
      <ul>
        <li>Test: <a href="/test">This is a test</a></li>
        <li>Another test: <a href="/another-test">This is another test</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(1)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Test", href: "/test" })
      expect(links[1]).to eq({ text: "Another test", href: "/another-test" })
    end

    it "extracts items before a heading is found to a section without text" do
      cooked_text = <<-HTML
      <ul>
        <li>Test: <a href="/test">This is a test</a></li>
        <li>Another test: <a href="/another-test">This is another test</a></li>
      </ul>
      <h1>First named section</h1>
      <ul>
        <li>Item: <a href="/item">This is a test</a></li>
        <li><a href="/another-item">Another item</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(2)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Test", href: "/test" })
      expect(links[1]).to eq({ text: "Another test", href: "/another-test" })

      named_section = sections[1]
      expect(named_section[:text]).to eq("First named section")

      links = named_section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Item", href: "/item" })
      expect(links[1]).to eq({ text: "Another item", href: "/another-item" })
    end

    it "extracts multiples sections" do
      cooked_text = <<-HTML
      <h1>First section</h1>
      <ul>
        <li>First item: <a href="/first-item">This is a test</a></li>
        <li>Another first item: <a href="/another-first-item">This is another test</a></li>
      </ul>
      <h1>Second section</h1>
      <ul>
        <li>Second item: <a href="/second-item">This is a test</a></li>
        <li><a href="/another-second-item">Another second item</a></li>
      </ul>
      <h1>Third section</h1>
      <ul>
        <li>Third item: <a href="/third-item">This is a test</a></li>
        <li><a href="/another-third-item">Another third item</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(3)

      section = sections[0]
      expect(section[:text]).to eq("First section")

      links = section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "First item", href: "/first-item" })
      expect(links[1]).to eq({ text: "Another first item", href: "/another-first-item" })

      section = sections[1]
      expect(section[:text]).to eq("Second section")

      links = section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Second item", href: "/second-item" })
      expect(links[1]).to eq({ text: "Another second item", href: "/another-second-item" })

      section = sections[2]
      expect(section[:text]).to eq("Third section")

      links = section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Third item", href: "/third-item" })
      expect(links[1]).to eq({ text: "Another third item", href: "/another-third-item" })
    end

    it "won't create sections for headings without lists" do
      cooked_text = <<-HTML
      <h1>First section</h1>
      <ul>
        <li>First item: <a href="/first-item">This is a test</a></li>
        <li>Another first item: <a href="/another-first-item">This is another test</a></li>
      </ul>
      <h1>Second section</h1>
      <ul>
        <li>Second item: This is a test</li>
        <li>Another second item</li>
      </ul>
      <h1>Third section</h1>
      <ul>
        <li>Third item: <a href="/third-item">This is a test</a></li>
        <li><a href="/another-third-item">Another third item</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(2)

      section = sections[0]
      expect(section[:text]).to eq("First section")

      links = section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "First item", href: "/first-item" })
      expect(links[1]).to eq({ text: "Another first item", href: "/another-first-item" })

      section = sections[1]
      expect(section[:text]).to eq("Third section")

      links = section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Third item", href: "/third-item" })
      expect(links[1]).to eq({ text: "Another third item", href: "/another-third-item" })
    end
  end

  context "when parsing lists" do
    it "if present, it will extract the text prior to the anchor as the text" do
      cooked_text = <<-HTML
      <ul>
        <li>Test: <a href="/test">This is a test</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(1)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(1)

      expect(links[0]).to eq({ text: "Test", href: "/test" })
    end

    it "it will use the anchor inner text as the text in case another one is not provided" do
      cooked_text = <<-HTML
      <ul>
        <li><a href="/test">This is a test</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(1)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(1)

      expect(links[0]).to eq({ text: "This is a test", href: "/test" })
    end

    it "it won't generate an item item a text can't be extracted" do
      cooked_text = <<-HTML
      <ul>
        <li><a href="/empty"></a></li>
        <li><a href="/test">Test</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(1)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(1)

      expect(links[0]).to eq({ text: "Test", href: "/test" })
    end

    it "extracts the index structure from HTML fragments containing multiple lists" do
      cooked_text = <<-HTML
      <ul>
        <li>Test: <a href="/test">This is a test</a></li>
      </ul>
      <ul>
        <li>Another test: <a href="/another-test">This is another test</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(1)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(2)

      expect(links[0]).to eq({ text: "Test", href: "/test" })
      expect(links[1]).to eq({ text: "Another test", href: "/another-test" })
    end

    it "won't extract items that do not contain an anchor" do
      cooked_text = <<-HTML
      <ul>
        <li>Test: This is a test></li>
        <li>Another test: <a href="/another-test">This is another test</a></li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      sections = p.sections

      expect(sections.size).to eq(1)

      root_section = sections.first
      expect(root_section[:text]).to be_nil

      links = root_section[:links]
      expect(links.size).to eq(1)

      expect(links[0]).to eq({ text: "Another test", href: "/another-test" })
    end
  end

  context "when parsing invalid content" do
    it "returns nil if parsing invalid content" do
      p = described_class.new("this is not valid HTML")
      expect(p.sections).to be_nil
    end

    it "returns nil if a list can't be found" do
      cooked_text = <<-HTML
      <h1>Test Heading</h1>
      <p>This is just a paragraph.</p>
      HTML

      p = described_class.new(cooked_text)
      expect(p.sections).to be_nil
    end

    it "returns nil if the lists don't contain anchors" do
      cooked_text = <<-HTML
      <ul>
        <li>Test</li>
      </ul>
      <ul>
        <li>Another test</li>
      </ul>
      HTML

      p = described_class.new(cooked_text)
      expect(p.sections).to be_nil
    end
  end
end
