import '../../api/generated/export.dart';
import '../products/suitability_logic.dart';

/// Pure helpers of the site baseline UI (ADR 0068): item values <-> form text, the one-line
/// summary, the tree, and the opportunity power grid fields.

Map<String, Object?> _asMap(Object? values) => values is Map
    ? {for (final e in values.entries) e.key.toString(): e.value}
    : const {};

String _formatNumber(Object? v) {
  if (v is int) return '$v';
  if (v is num) return v == v.truncateToDouble() ? '${v.toInt()}' : '$v';
  return v?.toString() ?? '';
}

/// The text of each input by definition key: one entry for number, select and text, two
/// (min, max) for a range. Missing values are empty.
Map<String, List<String>> rawFromValues(
  List<AttributeDefinition> defs,
  Object? values,
) {
  final m = _asMap(values);
  return {
    for (final d in defs)
      d.key: switch (d.kind) {
        DefinitionKind.range => () {
          final r = _asMap(m[d.key]);
          return [
            r['min'] == null ? '' : _formatNumber(r['min']),
            r['max'] == null ? '' : _formatNumber(r['max']),
          ];
        }(),
        DefinitionKind.number => [
          m[d.key] == null ? '' : _formatNumber(m[d.key]),
        ],
        _ => [m[d.key]?.toString() ?? ''],
      },
  };
}

class ValuesBuildResult {
  const ValuesBuildResult(this.values, this.errors);

  /// The complete `values` object for an item; a cleared input is simply absent.
  final Map<String, Object?> values;

  /// Errors by definition key; [values] must not be sent while this is not empty.
  final Map<String, AttrError> errors;
}

num? _number(String s) {
  final n = num.tryParse(s);
  return n != null && n.isFinite ? n : null;
}

/// Builds the values of an item from the inputs. A key without an (active) definition keeps its
/// stored value; every definition with a filled input becomes one value (empty = removed).
ValuesBuildResult buildValues({
  required List<AttributeDefinition> defs,
  required Object? existing,
  required Map<String, List<String>> raw,
}) {
  final defined = {for (final d in defs) d.key};
  final out = <String, Object?>{
    for (final e in _asMap(existing).entries)
      if (!defined.contains(e.key)) e.key: e.value,
  };
  final errors = <String, AttrError>{};
  for (final d in defs) {
    final v = [for (final s in raw[d.key] ?? const <String>[]) s.trim()];
    String at(int i) => i < v.length ? v[i] : '';
    switch (d.kind) {
      case DefinitionKind.range:
        final (lo, hi) = (at(0), at(1));
        if (lo.isEmpty && hi.isEmpty) break;
        if (lo.isEmpty || hi.isEmpty) {
          errors[d.key] = AttrError.rangeIncomplete;
          break;
        }
        final (a, b) = (_number(lo), _number(hi));
        if (a == null || b == null) {
          errors[d.key] = AttrError.notNumber;
        } else if (a > b) {
          errors[d.key] = AttrError.rangeOrder;
        } else {
          out[d.key] = {'min': a, 'max': b};
        }
      case DefinitionKind.number:
        if (at(0).isEmpty) break;
        final n = _number(at(0));
        if (n == null) {
          errors[d.key] = AttrError.notNumber;
        } else {
          out[d.key] = n;
        }
      case DefinitionKind.select:
        if (at(0).isEmpty) break;
        if (!d.options.any((o) => o.value == at(0))) {
          errors[d.key] = AttrError.notInOptions;
        } else {
          out[d.key] = at(0);
        }
      case DefinitionKind.text:
      case DefinitionKind.$unknown:
        if (at(0).isNotEmpty) out[d.key] = at(0);
    }
  }
  return ValuesBuildResult(out, errors);
}

/// A one-line summary of the stored values in definition order, for example
/// `Weight 120 kg · Dial 800–1000 mm · Motion Flying`. Keys without a definition follow as
/// `key value`.
String summarizeValues(List<AttributeDefinition> defs, Object? values) {
  final m = _asMap(values);
  final parts = <String>[];
  String withUnit(String text, AttributeDefinition d) =>
      (d.unit ?? '').isEmpty ? text : '$text ${d.unit}';
  for (final d in defs) {
    final v = m[d.key];
    if (v == null) continue;
    final text = switch (d.kind) {
      DefinitionKind.range => () {
        final r = _asMap(v);
        return withUnit(
          '${_formatNumber(r['min'])}–${_formatNumber(r['max'])}',
          d,
        );
      }(),
      DefinitionKind.number => withUnit(_formatNumber(v), d),
      DefinitionKind.select =>
        d.options.where((o) => o.value == v).map((o) => o.label).firstOrNull ??
            v.toString(),
      _ => v.toString(),
    };
    parts.add('${d.label} $text');
  }
  final known = {for (final d in defs) d.key};
  for (final e in m.entries) {
    if (!known.contains(e.key)) parts.add('${e.key} ${e.value}');
  }
  return parts.join(' · ');
}

/// All items of the tree, depth first.
List<BaselineItem> flattenBaseline(List<BaselineItem> tree) => [
  for (final i in tree) ...[i, ...flattenBaseline(i.children)],
];

/// The items [type] may be placed under: items whose type is an allowed parent type. The moving
/// item and its subtree are excluded (no cycles).
List<BaselineItem> parentCandidates(
  BaselineItemType type,
  List<BaselineItem> tree, {
  String? movingId,
}) {
  final excluded = <String>{};
  if (movingId != null) {
    for (final i in flattenBaseline(tree)) {
      if (i.id == movingId) {
        excluded.addAll(flattenBaseline([i]).map((e) => e.id));
      }
    }
  }
  return [
    for (final i in flattenBaseline(tree))
      if (type.allowedParentCodes.contains(i.typeCode) &&
          !excluded.contains(i.id))
        i,
  ];
}

/// The grid fields of an opportunity request: the chosen grid, or `clear` when a stored grid was
/// removed (ADR 0025: `clear_power_grid`); nothing when there is none.
({String? id, bool? clear}) powerGridInput({
  required String? stored,
  required String? chosen,
}) => chosen != null
    ? (id: chosen, clear: null)
    : (id: null, clear: stored != null ? true : null);
