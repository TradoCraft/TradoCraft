/// A saved search and filter selection of a list (ADR 0083, section 6).
library;

import 'dart:convert';

import 'filter_model.dart';

/// A named set of search text and filter selections.
class Favourite {
  const Favourite({
    required this.name,
    this.search = '',
    this.filters = FilterSelection.empty,
  });

  static const maxNameLength = 60;
  static const maxCount = 50;

  final String name;
  final String search;
  final FilterSelection filters;

  /// The favourite without filters or options that [defs] do not know.
  Favourite sanitized(List<FilterDef> defs) =>
      Favourite(name: name, search: search, filters: filters.sanitized(defs));

  Map<String, Object?> toJson() => {
    'name': name,
    'search': search,
    'filters': filters.toJson(),
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
      name: trimmed.length > maxNameLength
          ? trimmed.substring(0, maxNameLength)
          : trimmed,
      search: search is String ? search : '',
      filters: FilterSelection(filters),
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
      other.filters == filters;

  @override
  int get hashCode => Object.hash(name, search, filters);
}
