# frozen_string_literal: true

class ::DocCategories::DocIndexTopicParser
  HEADING_TAGS = %w[h1 h2 h3 h4 h5 h6]
  LIST_TAGS = %w[ol ul]

  def initialize(cooked_text)
    @cooked_text = cooked_text
    parse
  end

  def sections
    return if @sections.blank?
    return if (valid_sections = @sections.select { |section| section[:links].present? }).blank?

    valid_sections
  end

  private

  def parse
    target_nodes = Nokogiri.HTML5(@cooked_text).fragment.xpath("//body/*")
    target_nodes.each do |node|
      if heading?(node)
        add_section(node)
      elsif list?(node)
        add_list(node)
      end
    end
  end

  def heading?(node)
    HEADING_TAGS.include?(node.name)
  end

  def list?(node)
    LIST_TAGS.include?(node.name)
  end

  def list_item?(node)
    node.name == "li"
  end

  def add_section(node, root: false)
    @sections ||= []
    @sections << { text: (node.text.strip unless root), links: [] }
  end

  def add_list(node)
    node.children.each { |child| add_link(child) if list_item?(child) }
  end

  def add_link(item_node)
    nodes = item_node.children
    anchor = nodes.reverse.find { |child| child.name == "a" }
    return unless anchor

    title = nodes.first(nodes.index(anchor)).map(&:text).join.strip
    if title.present? && title.end_with?(":")
      title.chop!
    else
      title = anchor.text.strip
    end

    return if title.blank?

    add_section(nil, root: true) if @sections.blank?

    @sections.last[:links] << { text: title, href: anchor[:href] }
  end
end
