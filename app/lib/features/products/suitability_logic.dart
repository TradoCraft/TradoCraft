import '../../api/generated/export.dart';

/// Why an input of the suitability tab was refused.
enum AttrError { notNumber, rangeIncomplete, rangeOrder, notInOptions }

class AttrBuildResult {
  const AttrBuildResult(this.attributes, this.errors);

  /// The complete replacement list for `PUT /products/{id}/attributes`.
  final List<ProductAttribute> attributes;

  /// Errors by definition key; [attributes] must not be sent while this is not empty.
  final Map<String, AttrError> errors;
}

/// The text of each input by definition key: one entry for number, select and text, two
/// (min, max) for a range.
Map<String, List<String>> rawFromAttributes(
  List<AttributeDefinition> defs,
  List<ProductAttribute> stored,
) {
  final byKey = {for (final a in stored) a.key: a};
  return {
    for (final d in defs)
      d.key: switch (d.kind) {
        DefinitionKind.range => [
          byKey[d.key]?.valueMin ?? '',
          byKey[d.key]?.valueMax ?? '',
        ],
        _ => [byKey[d.key]?.value ?? ''],
      },
  };
}

/// Whether [value] may be saved for a select definition: it is one of the current options, or it
/// is the unchanged [stored] value (an option removed later must not block unrelated edits; the
/// server accepts it too). Anything newly entered must be a current option.
bool selectValueAllowed(AttributeDefinition d, String value, String? stored) =>
    d.options.any((o) => o.value == value) ||
    (stored != null && value == stored);

num? _number(String s) {
  final n = num.tryParse(s);
  return n != null && n.isFinite ? n : null;
}

/// Builds the replace-all attribute list: stored attributes without a definition are kept as
/// they are, every definition with a filled input becomes one attribute (empty = removed).
AttrBuildResult buildAttributes({
  required List<AttributeDefinition> defs,
  required List<ProductAttribute> existing,
  required Map<String, List<String>> raw,
}) {
  final defined = {for (final d in defs) d.key};
  final byKey = {for (final a in existing) a.key: a};
  final out = <ProductAttribute>[
    for (final a in existing)
      if (!defined.contains(a.key)) a,
  ];
  final errors = <String, AttrError>{};
  for (final d in defs) {
    final v = [for (final s in raw[d.key] ?? const <String>[]) s.trim()];
    String at(int i) => i < v.length ? v[i] : '';
    switch (d.kind) {
      case DefinitionKind.range:
        final lo = at(0);
        final hi = at(1);
        if (lo.isEmpty && hi.isEmpty) break;
        if (lo.isEmpty || hi.isEmpty) {
          errors[d.key] = AttrError.rangeIncomplete;
          break;
        }
        final a = _number(lo);
        final b = _number(hi);
        if (a == null || b == null) {
          errors[d.key] = AttrError.notNumber;
        } else if (a > b) {
          errors[d.key] = AttrError.rangeOrder;
        } else {
          out.add(
            ProductAttribute(
              key: d.key,
              kind: AttributeKind.range,
              value: '',
              unit: d.unit,
              valueMin: lo,
              valueMax: hi,
            ),
          );
        }
      case DefinitionKind.number:
        if (at(0).isEmpty) break;
        if (_number(at(0)) == null) {
          errors[d.key] = AttrError.notNumber;
        } else {
          out.add(
            ProductAttribute(
              key: d.key,
              kind: AttributeKind.number,
              value: at(0),
              unit: d.unit,
            ),
          );
        }
      case DefinitionKind.select:
        if (at(0).isEmpty) break;
        if (!selectValueAllowed(
          d,
          at(0),
          byKey[d.key]?.kind == AttributeKind.text ? byKey[d.key]?.value : null,
        )) {
          errors[d.key] = AttrError.notInOptions;
        } else {
          out.add(
            ProductAttribute(
              key: d.key,
              kind: AttributeKind.text,
              value: at(0),
            ),
          );
        }
      case DefinitionKind.text:
      case DefinitionKind.$unknown:
        if (at(0).isEmpty) break;
        out.add(
          ProductAttribute(key: d.key, kind: AttributeKind.text, value: at(0)),
        );
    }
  }
  return AttrBuildResult(out, errors);
}
