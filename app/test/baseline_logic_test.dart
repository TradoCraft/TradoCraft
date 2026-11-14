import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/api/generated/export.dart';
import 'package:tradocraft_app/features/opportunities/baseline_logic.dart';
import 'package:tradocraft_app/features/products/suitability_logic.dart';

AttributeDefinition _def(
  String key,
  String kind, {
  String? unit,
  List<Map<String, String>> options = const [],
}) => AttributeDefinition.fromJson({
  'id': 'd-$key',
  'key': key,
  'label': 'L-$key',
  'kind': kind,
  'unit': unit,
  'options': options,
  'scope': 'bell',
  'sort_order': 0,
  'active': true,
});

BaselineItem _item(
  String id,
  String type, {
  String? parent,
  List<BaselineItem> children = const [],
}) => BaselineItem(
  id: id,
  typeCode: type,
  parentId: parent,
  quantity: 1,
  sortOrder: 0,
  values: const <String, Object?>{},
  children: children,
  createdAt: DateTime(2027),
  updatedAt: DateTime(2027),
);

BaselineItemType _type(
  String code, {
  List<String> parents = const [],
  bool top = true,
  bool active = true,
}) => BaselineItemType(
  id: 't-$code',
  code: code,
  name: code,
  allowedParentCodes: parents,
  allowTopLevel: top,
  sortOrder: 0,
  active: active,
);

final _defs = [
  _def('weight', 'number', unit: 'kg'),
  _def('dial', 'range', unit: 'mm'),
  _def(
    'motion',
    'select',
    options: [
      {'label': 'Flying', 'value': 'flying'},
      {'label': 'Falling', 'value': 'falling'},
    ],
  ),
  _def('note', 'text'),
];

void main() {
  group('rawFromValues', () {
    test('formats stored values per kind and tolerates missing ones', () {
      final raw = rawFromValues(_defs, {
        'weight': 120,
        'dial': {'min': 800, 'max': 1000.5},
        'motion': 'flying',
      });
      expect(raw['weight'], ['120']);
      expect(raw['dial'], ['800', '1000.5']);
      expect(raw['motion'], ['flying']);
      expect(raw['note'], ['']);
      expect(rawFromValues(_defs, null)['dial'], ['', '']);
    });
  });

  group('buildValues', () {
    Map<String, List<String>> raw(Map<String, List<String>> over) => {
      'weight': [''],
      'dial': ['', ''],
      'motion': [''],
      'note': [''],
      ...over,
    };

    test('builds typed values and leaves out cleared fields', () {
      final r = buildValues(
        defs: _defs,
        existing: const {'weight': 5},
        raw: raw({
          'dial': ['800', '1000'],
          'motion': ['falling'],
          'note': ['  hi '],
        }),
      );
      expect(r.errors, isEmpty);
      expect(r.values, {
        'dial': {'min': 800, 'max': 1000},
        'motion': 'falling',
        'note': 'hi',
      });
      expect(r.values.containsKey('weight'), isFalse);
    });

    test('reports invalid input by key', () {
      final r = buildValues(
        defs: _defs,
        existing: const {},
        raw: raw({
          'weight': ['abc'],
          'dial': ['900', ''],
          'motion': ['sideways'],
        }),
      );
      expect(r.errors['weight'], AttrError.notNumber);
      expect(r.errors['dial'], AttrError.rangeIncomplete);
      expect(r.errors['motion'], AttrError.notInOptions);
      final order = buildValues(
        defs: _defs,
        existing: const {},
        raw: raw({
          'dial': ['10', '5'],
        }),
      );
      expect(order.errors['dial'], AttrError.rangeOrder);
    });

    test(
      'an unchanged stored select value stays valid when no longer an option',
      () {
        final same = buildValues(
          defs: _defs,
          existing: const {'motion': 'gone'},
          raw: raw({
            'motion': ['gone'],
          }),
        );
        expect(same.errors, isEmpty);
        expect(same.values['motion'], 'gone');
        final other = buildValues(
          defs: _defs,
          existing: const {'motion': 'gone'},
          raw: raw({
            'motion': ['sideways'],
          }),
        );
        expect(other.errors['motion'], AttrError.notInOptions);
        final fresh = buildValues(
          defs: _defs,
          existing: const {},
          raw: raw({
            'motion': ['gone'],
          }),
        );
        expect(fresh.errors['motion'], AttrError.notInOptions);
      },
    );

    test('keeps stored values of keys that have no active definition', () {
      final r = buildValues(
        defs: [_defs.first],
        existing: const {'old': 'x', 'weight': 1},
        raw: {
          'weight': ['2'],
        },
      );
      expect(r.values, {'old': 'x', 'weight': 2});
    });
  });

  group('summarizeValues', () {
    test(
      'one line with units, option labels and ranges, in definition order',
      () {
        final s = summarizeValues(_defs, {
          'motion': 'flying',
          'weight': 120.0,
          'dial': {'min': 800, 'max': 1000},
          'note': 'x',
        });
        expect(
          s,
          'L-weight 120 kg · L-dial 800–1000 mm · L-motion Flying · L-note x',
        );
      },
    );

    test('is empty without values and falls back to the raw key/value', () {
      expect(summarizeValues(_defs, const {}), '');
      expect(summarizeValues(const [], {'a': 1}), 'a 1');
    });
  });

  group('tree helpers', () {
    final bell = _item('b1', 'bell', parent: 'g1');
    final group = _item('g1', 'bell_group', children: [bell]);
    final dial = _item('d1', 'clock_dial');
    final tree = [group, dial];

    test('flattenBaseline walks depth first', () {
      expect([for (final i in flattenBaseline(tree)) i.id], ['g1', 'b1', 'd1']);
    });

    test('parentCandidates only offers items of an allowed parent type', () {
      final bellType = _type('bell', parents: ['bell_group']);
      expect([for (final i in parentCandidates(bellType, tree)) i.id], ['g1']);
      expect(parentCandidates(_type('clock_dial'), tree), isEmpty);
    });

    test('parentCandidates excludes the item itself and its subtree', () {
      final groupType = _type('bell_group', parents: ['bell_group']);
      expect(parentCandidates(groupType, tree, movingId: 'g1'), isEmpty);
    });
  });

  group('powerGridInput', () {
    test('sends the chosen grid, or a clear when a stored grid is removed', () {
      expect(powerGridInput(stored: null, chosen: null), (
        id: null,
        clear: null,
      ));
      expect(powerGridInput(stored: null, chosen: 'g'), (id: 'g', clear: null));
      expect(powerGridInput(stored: 'g', chosen: 'g'), (id: 'g', clear: null));
      expect(powerGridInput(stored: 'g', chosen: null), (
        id: null,
        clear: true,
      ));
    });
  });

  group('boolean attributes', () {
    final defs = [_def('lit', 'boolean'), _def('weight', 'number', unit: 'kg')];

    test('raw text is true, false or empty', () {
      expect(rawFromValues(defs, {'lit': true})['lit'], ['true']);
      expect(rawFromValues(defs, {'lit': false})['lit'], ['false']);
      expect(rawFromValues(defs, const {})['lit'], ['']);
    });

    test('builds a bool, an empty input clears it, other text is refused', () {
      Map<String, List<String>> raw(String lit) => {
        'lit': [lit],
        'weight': [''],
      };
      expect(
        buildValues(defs: defs, existing: const {}, raw: raw('true')).values,
        {'lit': true},
      );
      expect(
        buildValues(defs: defs, existing: const {}, raw: raw('false')).values,
        {'lit': false},
      );
      expect(
        buildValues(defs: defs, existing: {'lit': true}, raw: raw('')).values,
        isEmpty,
      );
      expect(
        buildValues(defs: defs, existing: const {}, raw: raw('maybe')).errors,
        {'lit': AttrError.notInOptions},
      );
    });

    test('the summary shows the given yes and no words', () {
      expect(
        summarizeValues(defs, {'lit': true}, yes: 'Yes', no: 'No'),
        'L-lit Yes',
      );
      expect(
        summarizeValues(defs, {'lit': false}, yes: 'Ja', no: 'Nee'),
        'L-lit Nee',
      );
    });
  });

  group('missingAttributes', () {
    test('lists the active definitions that have no value, in order', () {
      final defs = [
        _def('a', 'number'),
        _def('b', 'boolean'),
        _def(
          'c',
          'select',
          options: [
            {'label': 'X', 'value': 'x'},
          ],
        ),
        _def('d', 'range'),
      ];
      final missing = missingAttributes(defs, {
        'b': false, // false is a value, not missing
        'd': {'min': 1, 'max': 2},
      });
      expect([for (final d in missing) d.key], ['a', 'c']);
    });

    test('inactive definitions are not asked for', () {
      final d = AttributeDefinition.fromJson({
        'id': 'x',
        'key': 'old',
        'label': 'Old',
        'kind': 'text',
        'options': <Object?>[],
        'scope': 'bell',
        'sort_order': 0,
        'active': false,
      });
      expect(missingAttributes([d], const {}), isEmpty);
    });
  });
}
