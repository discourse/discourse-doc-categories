import Component from "@glimmer/component";
import { i18n } from "discourse-i18n";
import DocCategoryIndexTab from "./doc-category-index-tab.gjs";

export default class DocCategoryIndexSettings extends Component {
  static shouldRender({ category, categoryType }, { siteSettings }) {
    return (
      categoryType === "documentation" &&
      category?.categoryTypes?.documentation &&
      siteSettings.doc_categories_index_editor &&
      (!category.id || siteSettings.doc_categories_enabled)
    );
  }

  <template>
    <h3>{{i18n "doc_categories.category_settings.tab_title"}}</h3>
    <DocCategoryIndexTab
      @category={{@outletArgs.category}}
      @form={{@outletArgs.form}}
      @registerAfterReset={{@outletArgs.registerAfterReset}}
      @registerValidator={{@outletArgs.registerValidator}}
      @transientData={{@outletArgs.transientData}}
    />
  </template>
}
