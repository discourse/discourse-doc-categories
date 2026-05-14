import SortableColumn from "discourse/components/topic-list/header/sortable-column";
import { i18n } from "discourse-i18n";

const DocUpdatedHeaderCell = <template>
  <SortableColumn
    @sortable={{@sortable}}
    @number="true"
    @order="activity"
    @activeOrder={{@activeOrder}}
    @changeSort={{@changeSort}}
    @ascending={{@ascending}}
    @forceName={{i18n "doc_categories.simple_mode.updated"}}
  />
</template>;

export default DocUpdatedHeaderCell;
