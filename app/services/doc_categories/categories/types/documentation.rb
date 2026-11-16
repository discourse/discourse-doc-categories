# frozen_string_literal: true

module DocCategories
  module Categories
    module Types
      class Documentation < ::Categories::Types::Base
        CUSTOM_FIELD = "doc_categories_documentation"

        type_id :documentation

        class << self
          def enable_plugin
            SiteSetting.doc_categories_enabled = true
          end

          def plugin_enabled?
            SiteSetting.doc_categories_enabled
          end

          def visible?
            SiteSetting.doc_categories_index_editor
          end

          alias_method :available?, :visible?

          def category_matches?(category)
            visible? && plugin_enabled? && category.custom_fields[CUSTOM_FIELD] == true
          end

          def find_matches
            return ::Category.none if !visible? || !plugin_enabled?

            ::Category.where(
              id: ::CategoryCustomField.where(name: CUSTOM_FIELD, value: "t").select(:category_id),
            )
          end

          def configure_category(category, guardian:, configuration_values: {})
            category.with_lock do
              category.custom_fields[CUSTOM_FIELD] = true
              category.save!

              if category.doc_categories_index&.index_topic_id.nil?
                DocCategories::CategoryIndexManager.call!(
                  params: {
                    category_id: category.id,
                    topic_id: DocCategories::Index::INDEX_TOPIC_ID_DIRECT,
                  },
                )
              end
            end
          end

          def unconfigure_category(category, guardian:)
            category.custom_fields.delete(CUSTOM_FIELD)
            category.save!
          end

          def configuration_schema
            {
              category_custom_fields: {
                CUSTOM_FIELD.to_sym => {
                  default: true,
                  type: :bool,
                  label: I18n.t("category_types.documentation.name"),
                  show_on_create: false,
                  show_on_edit: false,
                },
              },
            }
          end

          def icon
            "book"
          end

          def svg_icon
            "book"
          end
        end
      end
    end
  end
end
