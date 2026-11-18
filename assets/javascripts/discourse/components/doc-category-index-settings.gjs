import Component from "@glimmer/component";
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
    <DocCategoryIndexTab
      @category={{@outletArgs.category}}
      @form={{@outletArgs.form}}
      @registerAfterReset={{@outletArgs.registerAfterReset}}
      @registerValidator={{@outletArgs.registerValidator}}
      @transientData={{@outletArgs.transientData}}
    />
  </template>
}
