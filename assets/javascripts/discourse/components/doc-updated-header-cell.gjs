import SortableColumn from "discourse/components/topic-list/header/sortable-column";
import { i18n } from "discourse-i18n";

const DocUpdatedHeaderCell = <template>
  <SortableColumn
    @activeOrder={{@activeOrder}}
    @ascending={{@ascending}}
    @changeSort={{@changeSort}}
    @forceName={{i18n "doc_categories.simple_mode.updated"}}
    @number="true"
    @order="activity"
    @sortable={{@sortable}}
  />
</template>;

export default DocUpdatedHeaderCell;
