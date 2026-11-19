/// Filters of a list (ADR 0083): the definition a page declares and the pure selection state.
library;

import 'package:flutter/foundation.dart' show setEquals;

/// One filter a list offers: an API key, a label and a fixed list of `(value, label)` options.
///
/// The selected values of one filter combine with OR, different filters with AND.
class FilterDef {
  const FilterDef({
    required this.key,
    required this.label,
    required this.options,
  });

  /// The name of the query parameter.
  final String key;
  final String label;

  /// The choices as `(value, label)`; the order is the order of the menu and of the chips.
  final List<(String value, String label)> options;

  bool hasOption(String value) => options.any((o) => o.$1 == value);

  /// The label of [value]; the value itself when it is not an option.
  String optionLabel(String value) {
    for (final o in options) {
      if (o.$1 == value) return o.$2;
    }
    return value;
  }
}

/// What one facet chip shows: the filter [key] it removes and its [text].
class FilterChipData {
  const FilterChipData(this.key, this.filterLabel, this.text);
  final String key;
  final String filterLabel;

  /// For example `Status: Draft or Sent`.
  final String text;
}

/// The selected values per filter key. Immutable: every change returns a new selection.
class FilterSelection {
  const FilterSelection._(this._values);

  static const empty = FilterSelection._({});

  /// Copies [values]; filters without a value are dropped.
  factory FilterSelection(Map<String, Set<String>> values) {
    final copy = <String, Set<String>>{
      for (final e in values.entries)
        if (e.value.isNotEmpty) e.key: Set.unmodifiable(e.value),
    };
    return copy.isEmpty ? empty : FilterSelection._(Map.unmodifiable(copy));
  }

  final Map<String, Set<String>> _values;

  bool get isEmpty => _values.isEmpty;
  bool get isNotEmpty => _values.isNotEmpty;

  /// The keys that have a selection.
  Iterable<String> get keys => _values.keys;

  /// The number of selected values over all filters.
  int get count => _values.values.fold(0, (a, s) => a + s.length);

  Set<String> of(String key) => _values[key] ?? const {};

  bool contains(String key, String value) => of(key).contains(value);

  /// Selects [value] of [key], or unselects it when it is selected.
  FilterSelection toggle(String key, String value) {
    final next = {
      for (final e in _values.entries) e.key: {...e.value},
    };
    final set = next.putIfAbsent(key, () => {});
    if (!set.remove(value)) set.add(value);
    return FilterSelection(next);
  }

  /// Drops the whole selection of [key].
  FilterSelection without(String key) => FilterSelection({
    for (final e in _values.entries)
      if (e.key != key) e.key: e.value,
  });

  FilterSelection cleared() => empty;

  /// Keeps only the filters and options that [defs] know.
  FilterSelection sanitized(List<FilterDef> defs) {
    final next = <String, Set<String>>{};
    for (final d in defs) {
      final v = of(d.key).where(d.hasOption).toSet();
      if (v.isNotEmpty) next[d.key] = v;
    }
    return FilterSelection(next);
  }

  /// One chip per filter with a selection, in the order of [defs]; the values in option order.
  /// [or] is the word between values ("or"). Keys that [defs] do not know give no chip.
  List<FilterChipData> chips(List<FilterDef> defs, String or) => [
    for (final d in defs)
      if (of(d.key).isNotEmpty)
        FilterChipData(d.key, d.label, '${d.label}: ${_valueText(d, or)}'),
  ];

  String _valueText(FilterDef d, String or) => [
    for (final o in d.options)
      if (of(d.key).contains(o.$1)) o.$2,
  ].join(' $or ');

  /// The key of the last chip in the order of [defs], or null.
  String? lastKey(List<FilterDef> defs) {
    String? last;
    for (final d in defs) {
      if (of(d.key).isNotEmpty) last = d.key;
    }
    return last;
  }

  /// The `ListQuery.filters` map: key to the set of selected values.
  Map<String, Object?> toQuery() => {
    for (final e in _values.entries) e.key: Set<String>.of(e.value),
  };

  /// A stable text, equal for equal selections (used to tell queries apart).
  String get stableKey {
    final keys = _values.keys.toList()..sort();
    return keys
        .map((k) => '$k=${(_values[k]!.toList()..sort()).join(',')}')
        .join(';');
  }

  Map<String, List<String>> toJson() => {
    for (final e in _values.entries) e.key: (e.value.toList()..sort()),
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FilterSelection || other._values.length != _values.length) {
      return false;
    }
    for (final e in _values.entries) {
      final o = other._values[e.key];
      if (o == null || !setEquals(o, e.value)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAllUnordered([
    for (final e in _values.entries)
      Object.hash(e.key, Object.hashAllUnordered(e.value)),
  ]);

  @override
  String toString() => 'FilterSelection($stableKey)';
}
