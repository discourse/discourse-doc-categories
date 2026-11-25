# frozen_string_literal: true

module DocCategories
  class SidebarLink < ActiveRecord::Base
    self.table_name = "doc_categories_sidebar_links"
    self.ignored_columns += %i[icon]

    MAX_HREF_LENGTH = 2000
    MAX_TITLE_LENGTH = 255
    TOPIC_LOOKUP_BATCH_SIZE = 500

    belongs_to :sidebar_section,
               class_name: "DocCategories::SidebarSection",
               foreign_key: :sidebar_section_id,
               inverse_of: :sidebar_links

    belongs_to :topic, -> { with_deleted }, optional: true

    scope :auto_indexed, -> { where(auto_indexed: true) }
    scope :auto_indexed_for_topic,
          ->(topic_id) { auto_indexed.joins(sidebar_section: :index).where(topic_id:) }

    before_validation :populate_href_from_topic, if: -> { topic.present? && href.blank? }

    validates :sidebar_section_id, presence: true
    validates :position,
              presence: true,
              uniqueness: {
                scope: :sidebar_section_id,
              },
              numericality: {
                only_integer: true,
                greater_than: -1,
              }
    validates :title, length: { maximum: MAX_TITLE_LENGTH }
    validates :href, length: { maximum: MAX_HREF_LENGTH }, presence: true
    validate :topic_not_deleted, unless: :position_only_change?

    def self.referenced_topic_id(topic_id, href)
      topic_id || DocCategories::Url.extract_topic_id_from_url(href)
    end

    def self.targeting_topics(topic_ids)
      href_link_ids =
        topic_ids
          .each_slice(TOPIC_LOOKUP_BATCH_SIZE)
          .flat_map do |ids|
            # The SQL filter narrows the candidates. Route recognition verifies the destination.
            path = "/t/(?:[^/?#]+/)?(?:#{ids.join("|")})(?:[./?#]|$)"
            matching_ids = ids.to_set
            where("href ~ ?", path)
              .pluck(:id, :href)
              .filter_map { |id, href| id if matching_ids.include?(referenced_topic_id(nil, href)) }
          end
      where(topic_id: topic_ids).or(where(id: href_link_ids))
    end

    def referenced_topic_id
      self.class.referenced_topic_id(topic_id, href)
    end

    private

    def position_only_change?
      persisted? && changes_to_save.keys == ["position"]
    end

    def topic_not_deleted
      return if topic.nil?
      return if !topic.trashed?

      errors.add(:topic_id, "cannot reference a deleted topic")
    end

    def populate_href_from_topic
      self.href = topic.relative_url
    end
  end
end

# == Schema Information
#
# Table name: doc_categories_sidebar_links
#
#  id                 :bigint           not null, primary key
#  auto_indexed       :boolean          default(FALSE), not null
#  href               :text             not null
#  position           :integer          not null
#  title              :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  sidebar_section_id :bigint           not null
#  topic_id           :bigint
#
# Indexes
#
#  idx_doc_categories_links_on_section_id_and_position  (sidebar_section_id,position) UNIQUE
#  index_doc_categories_sidebar_links_on_topic_id       (topic_id)
#
