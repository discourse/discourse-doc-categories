import { fn } from "@ember/helper";
import DMenu from "discourse/float-kit/components/d-menu";
import DButton from "discourse/ui-kit/d-button";
import DDropdownMenu from "discourse/ui-kit/d-dropdown-menu";
import icon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

const DocIndexModeSelector = <template>
  <DMenu
    @identifier="doc-index-mode-selector"
    @triggerClass="btn-default doc-category-index-tab__mode-trigger"
  >
    <:trigger>
      <span>{{@currentModeLabel}}</span>
      {{icon "angle-down"}}
    </:trigger>
    <:content as |dMenu|>
      <DDropdownMenu as |dropdown|>
        {{#if @showEditorOption}}
          <dropdown.item>
            <DButton
              class="--with-description doc-category-index-tab__mode-option"
              @action={{fn @onSwitchToDirect dMenu}}
            >
              <div class="doc-category-index-tab__mode-option-texts">
                <span class="doc-category-index-tab__mode-option-label">{{i18n
                    "doc_categories.category_settings.index_editor.mode_direct"
                  }}</span>
                <span
                  class="doc-category-index-tab__mode-option-description"
                >{{i18n
                    "doc_categories.category_settings.index_editor.mode_direct_description"
                  }}</span>
              </div>
            </DButton>
          </dropdown.item>
        {{/if}}
        <dropdown.item>
          <DButton
            class="--with-description doc-category-index-tab__mode-option"
            @action={{fn @onSwitchToTopic dMenu}}
          >
            <div class="doc-category-index-tab__mode-option-texts">
              <span class="doc-category-index-tab__mode-option-label">{{i18n
                  "doc_categories.category_settings.index_editor.mode_topic"
                }}</span>
              <span
                class="doc-category-index-tab__mode-option-description"
              >{{i18n
                  "doc_categories.category_settings.index_editor.mode_topic_description"
                }}</span>
            </div>
          </DButton>
        </dropdown.item>
        <dropdown.item>
          <DButton
            class="--with-description doc-category-index-tab__mode-option"
            @action={{fn @onSwitchToNone dMenu}}
          >
            <div class="doc-category-index-tab__mode-option-texts">
              <span class="doc-category-index-tab__mode-option-label">{{i18n
                  "doc_categories.category_settings.index_editor.mode_none"
                }}</span>
              <span
                class="doc-category-index-tab__mode-option-description"
              >{{i18n
                  "doc_categories.category_settings.index_editor.mode_none_description"
                }}</span>
            </div>
          </DButton>
        </dropdown.item>
      </DDropdownMenu>
    </:content>
  </DMenu>
</template>;

export default DocIndexModeSelector;
