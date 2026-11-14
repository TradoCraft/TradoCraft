import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/api/generated/export.dart';
import 'package:tradocraft_app/features/products/suitability_logic.dart';

AttributeDefinition def(
  String key,
  DefinitionKind kind, {
  String? unit,
  List<SelectOption> options = const [],
}) => AttributeDefinition(
  active: true,
  id: 'd-$key',
  key: key,
  kind: kind,
  label: key,
  options: options,
  scope: 'product',
  sortOrder: 0,
  unit: unit,
);

ProductAttribute attr(
  String key,
  AttributeKind kind,
  String value, {
  String? min,
  String? max,
}) => ProductAttribute(
  key: key,
  kind: kind,
  value: value,
  valueMin: min,
  valueMax: max,
);

void main() {
  final defs = [
    def('weight', DefinitionKind.number, unit: 'kg'),
    def('dial', DefinitionKind.range, unit: 'mm'),
    def(
      'motion',
      DefinitionKind.select,
      options: const [
        SelectOption(label: 'Flying', value: 'flying'),
        SelectOption(label: 'Falling', value: 'falling'),
      ],
    ),
    def('note', DefinitionKind.text),
  ];

  test('builds one attribute per filled definition', () {
    final r = buildAttributes(
      defs: defs,
      existing: const [],
      raw: {
        'weight': [' 12.5 '],
        'dial': ['600', '1250'],
        'motion': ['flying'],
        'note': ['  hello '],
      },
    );
    expect(r.errors, isEmpty);
    final json = r.attributes.map((a) => a.toJson()).toList();
    expect(json, [
      {'key': 'weight', 'kind': AttributeKind.number, 'unit': 'kg', 'value': '12.5'},
      {
        'key': 'dial',
        'kind': AttributeKind.range,
        'unit': 'mm',
        'value': '',
        'value_min': '600',
        'value_max': '1250',
      },
      {'key': 'motion', 'kind': AttributeKind.text, 'value': 'flying'},
      {'key': 'note', 'kind': AttributeKind.text, 'value': 'hello'},
    ]);
  });

  test('empty inputs are left out', () {
    final r = buildAttributes(
      defs: defs,
      existing: const [],
      raw: {'weight': [''], 'dial': ['', ''], 'motion': [''], 'note': [' ']},
    );
    expect(r.errors, isEmpty);
    expect(r.attributes, isEmpty);
  });

  test('attributes without a definition are preserved, defined ones replaced', () {
    final r = buildAttributes(
      defs: defs,
      existing: [
        attr('color', AttributeKind.text, 'red'),
        attr('weight', AttributeKind.number, '1'),
        attr('flag', AttributeKind.boolean, 'true'),
      ],
      raw: {'weight': ['2']},
    );
    expect(r.attributes.map((a) => a.key).toList(), ['color', 'flag', 'weight']);
    expect(r.attributes.last.value, '2');
  });

  test('a cleared defined attribute is removed but unknown ones stay', () {
    final r = buildAttributes(
      defs: defs,
      existing: [
        attr('color', AttributeKind.text, 'red'),
        attr('weight', AttributeKind.number, '1'),
      ],
      raw: {'weight': ['']},
    );
    expect(r.attributes.map((a) => a.key).toList(), ['color']);
  });

  test('validation errors are reported per key', () {
    final r = buildAttributes(
      defs: defs,
      existing: const [],
      raw: {
        'weight': ['abc'],
        'dial': ['600', ''],
        'motion': ['balanced'],
      },
    );
    expect(r.errors, {
      'weight': AttrError.notNumber,
      'dial': AttrError.rangeIncomplete,
      'motion': AttrError.notInOptions,
    });
    expect(
      buildAttributes(
        defs: defs,
        existing: const [],
        raw: {'dial': ['20', '10']},
      ).errors,
      {'dial': AttrError.rangeOrder},
    );
    expect(
      buildAttributes(
        defs: defs,
        existing: const [],
        raw: {'dial': ['a', '10']},
      ).errors,
      {'dial': AttrError.notNumber},
    );
  });

  test('raw values are read back from stored attributes', () {
    final raw = rawFromAttributes(defs, [
      attr('weight', AttributeKind.number, '7'),
      attr('dial', AttributeKind.range, '', min: '600', max: '900'),
      attr('motion', AttributeKind.text, 'falling'),
    ]);
    expect(raw, {
      'weight': ['7'],
      'dial': ['600', '900'],
      'motion': ['falling'],
      'note': [''],
    });
  });
}
