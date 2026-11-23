import Category from "discourse/models/category";
import { selectKitOptions } from "discourse/select-kit/components/select-kit";
import TopicChooser from "discourse/select-kit/components/topic-chooser";
import { i18n } from "discourse-i18n";

@selectKitOptions({ docCategoryId: null })
export default class DocCategoryTopicChooser extends TopicChooser {
  modifyContent(content) {
    return super.modifyContent(content).filter((topic) => this.#allowed(topic));
  }

  validateSelect(topic) {
    if (!super.validateSelect(topic)) {
      return false;
    }
    if (!this.#allowed(topic)) {
      this.addError(
        i18n(
          "doc_categories.category_settings.sidebar_structure_editor.private_topics_help"
        )
      );
      return false;
    }
    return true;
  }

  #allowed(topic) {
    const category = Category.findById(topic.category_id);
    return (
      !!category &&
      (category.id === this.selectKit.options.docCategoryId ||
        category.read_restricted === false)
    );
  }
}
