# frozen_string_literal: true

task "javascript:update_constants" => :environment do
  write_template(
    "../plugins/discourse-doc-categories/assets/javascripts/discourse/lib/constants.js",
    "update_constants",
    <<~JS,
      export const MAX_SECTIONS = #{DocCategories::Index::MAX_SECTIONS};
      export const MAX_LINKS_PER_SECTION = #{DocCategories::Index::MAX_LINKS_PER_SECTION};
    JS
  )
end
