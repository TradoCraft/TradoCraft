/// A saved search and filter selection of a list (ADR 0083, section 6).
library;

import 'dart:convert';

import 'package:characters/characters.dart';

import 'filter_model.dart';
import 'group_model.dart';

/// A named set of search text and filter selections.
class Favourite {
  const Favourite({
    required this.name,
    this.search = '',
    this.filters = FilterSelection.empty,
    this.groupBy,
  });

  static const maxNameLength = 60;
  static const maxCount = 50;

  final String name;
  final String search;
  final FilterSelection filters;

  /// The key of the grouping (ADR 0089); null: not grouped.
  final String? groupBy;

  /// The favourite without filters or options that [defs] do not know, and without a grouping
  /// that is not one of [groups].
  Favourite sanitized(
    List<FilterDef> defs, {
    List<GroupDef> groups = const [],
  }) => Favourite(
    name: name,
    search: search,
    filters: filters.sanitized(defs),
    groupBy: groups.any((g) => g.key == groupBy) ? groupBy : null,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'search': search,
    'filters': filters.toJson(),
    if (groupBy != null) 'groupBy': groupBy,
  };

  /// Reads one favourite; null when [j] is damaged. Unknown keys are ignored.
  static Favourite? fromJson(Object? j) {
    if (j is! Map) return null;
    final name = j['name'];
    if (name is! String) return null;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final search = j['search'];
    final raw = j['filters'];
    final group = j['groupBy'];
    final filters = <String, Set<String>>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is List) {
          final s = {
            for (final x in v)
              if (x is String && x.isNotEmpty) x,
          };
          if (s.isNotEmpty) filters[k] = s;
        }
      });
    }
    return Favourite(
      name: trimmed.characters.take(maxNameLength).toString(),
      search: search is String ? search : '',
      filters: FilterSelection(filters),
      groupBy: group is String && group.isNotEmpty ? group : null,
    );
  }

  /// The stored list; empty for null or a damaged value, damaged entries are skipped.
  static List<Favourite> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      final items = j is Map ? j['favourites'] : j;
      if (items is! List) return const [];
      final out = <Favourite>[];
      for (final i in items) {
        final f = fromJson(i);
        if (f != null && !out.any((o) => o.name == f.name)) out.add(f);
        if (out.length >= maxCount) break;
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<Favourite> list) => jsonEncode({
    'favourites': [for (final f in list) f.toJson()],
  });

  /// [list] with [f] added, or replacing the favourite of the same name.
  static List<Favourite> upsert(List<Favourite> list, Favourite f) {
    final i = list.indexWhere((o) => o.name == f.name);
    if (i >= 0) return [...list]..[i] = f;
    final all = [...list, f];
    return all.length > maxCount ? all.sublist(all.length - maxCount) : all;
  }

  @override
  bool operator ==(Object other) =>
      other is Favourite &&
      other.name == name &&
      other.search == search &&
      other.filters == filters &&
      other.groupBy == groupBy;

  @override
  int get hashCode => Object.hash(name, search, filters, groupBy);
}
