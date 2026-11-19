/// Grouping of a list (ADR 0084): the definition a page declares and the pure header labels.
library;

import 'filter_model.dart';

/// One grouping a list offers: the API key (also the key of a [FilterDef] of the list) and a label.
class GroupDef {
  const GroupDef(this.key, this.label);

  /// The `group_by` value; the rows of one group are the list filtered to one value of this key.
  final String key;
  final String label;
}

/// One group as the groups endpoint returns it: the filter [value] and the number of [count] rows.
class GroupBucket {
  const GroupBucket(this.value, this.count);
  final String value;
  final int count;
}

/// What one group header shows.
class GroupHeader {
  const GroupHeader(this.value, this.label, this.count);
  final String value;
  final String label;
  final int count;
}

/// The headers for [buckets], in the order given. The label is the option label of [def]; a value
/// without an option (or no [def]) shows the raw value.
List<GroupHeader> groupHeaders(List<GroupBucket> buckets, FilterDef? def) => [
  for (final b in buckets)
    GroupHeader(b.value, def?.optionLabel(b.value) ?? b.value, b.count),
];
