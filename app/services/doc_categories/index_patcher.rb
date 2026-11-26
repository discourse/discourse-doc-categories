# frozen_string_literal: true

module DocCategories
  class IndexPatcher
    include Service::Base

    OPERATIONS = {
      "add_section" => %i[title],
      "move_section" => %i[section_id placement relative_section_id],
      "add_topic_links" => %i[section_id topic_ids],
      "remove_section" => %i[section_id],
      "remove_topic_link" => %i[section_id topic_id],
    }.freeze
    OPTIONAL_FIELDS = { "add_section" => %i[topic_ids placement relative_section_id] }.freeze
    PLACEMENTS = %w[before after inside].freeze

    params do
      attribute :category_id, :integer
      attribute :operation, :string
      attribute :title, :string
      attribute :section_id, :integer
      attribute :relative_section_id, :integer
      attribute :placement, :string
      attribute :topic_ids
      attribute :topic_id, :integer

      validates :category_id, numericality: { only_integer: true, greater_than: 0 }
      validates :operation, inclusion: { in: OPERATIONS.keys }
      validates :title, length: { maximum: SidebarSection::MAX_TITLE_LENGTH }, allow_nil: true
      validates :section_id,
                :relative_section_id,
                :topic_id,
                numericality: {
                  only_integer: true,
                  greater_than: 0,
                },
                allow_nil: true
      validates :placement, inclusion: { in: PLACEMENTS }, allow_nil: true
      validate :validate_operation_fields
      validate :valid_section_placement
      validate :valid_topic_ids

      private

      def validate_operation_fields
        required_fields = OPERATIONS[operation]
        return if required_fields.nil?

        required_fields.each { |field| errors.add(field, :blank) if public_send(field).blank? }

        allowed_fields =
          %i[category_id operation] + required_fields + OPTIONAL_FIELDS.fetch(operation, [])
        (self.class.attribute_names - allowed_fields.map(&:to_s)).each do |field|
          errors.add(field, :invalid) if provided?(field)
        end
      end

      def valid_section_placement
        return if operation != "add_section"

        errors.add(:placement, :blank) if relative_section_id && placement.nil?
        errors.add(:relative_section_id, :blank) if placement && relative_section_id.nil?
      end

      def valid_topic_ids
        return if topic_ids.nil?
        if topic_ids.is_a?(Array) &&
             topic_ids.size <= DocCategories::Index::MAX_LINKS_PER_SECTION &&
             topic_ids.all? { |id| id.is_a?(Integer) && id.positive? } &&
             topic_ids.uniq == topic_ids
          return
        end

        errors.add(:topic_ids, :invalid)
      end
    end

    policy :can_edit_index

    transaction do
      model :category
      model :index, optional: true
      policy :index_editor_enabled
      policy :not_topic_managed
      model :patch, :build_patch
      step :prepare_patch
      only_if(:index_changed) { step :apply_patch }
    end

    only_if(:index_changed) { step :publish_changes }

    private

    def can_edit_index(guardian:)
      guardian&.is_admin?
    end

    def fetch_category(params:, guardian:)
      category = ::Category.lock.find_by(id: params.category_id)
      category if guardian.can_see_category?(category)
    end

    def fetch_index(category:)
      DocCategories::Index.find_by(category:)
    end

    def index_editor_enabled(index:)
      SiteSetting.doc_categories_enabled &&
        (UpcomingChanges.enabled?(:doc_categories_index_editor) || index&.mode_direct?)
    end

    def not_topic_managed(index:)
      !index&.mode_topic?
    end

    def build_patch(category:, index:, params:)
      Patch.new(category:, index:, params:)
    end

    def prepare_patch(patch:)
      patch.prepare!
    rescue Patch::Invalid => error
      fail!(error.message)
    end

    def index_changed(patch:)
      patch.changes_index?
    end

    def apply_patch(patch:)
      DocCategories::Action::ApplyPatch.call(patch:)
    rescue ActiveRecord::RecordNotUnique
      fail!(I18n.t("doc_categories.errors.index_patch_conflict"))
    end

    def publish_changes(category:)
      DocCategories::Action::PublishSidebarChanges.call(category_ids: [category.id])
    end
  end
end
