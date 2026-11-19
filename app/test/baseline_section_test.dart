import 'dart:async';
import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/opportunities/baseline_section.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';

import 'fake_http.dart';

Map<String, Object?> _type(
  String code,
  String name, {
  List<String> parents = const [],
  bool top = true,
  bool active = true,
}) => {
  'id': 't-$code',
  'code': code,
  'name': name,
  'allowed_parent_codes': parents,
  'allow_top_level': top,
  'sort_order': 0,
  'active': active,
};

Map<String, Object?> _def(
  String scope,
  String key,
  String kind, {
  String? unit,
  List<Map<String, String>> options = const [],
  bool active = true,
}) => {
  'id': 'd-$scope-$key',
  'key': key,
  'label': 'L-$key',
  'kind': kind,
  'unit': unit,
  'options': options,
  'scope': scope,
  'sort_order': 0,
  'active': active,
};

Map<String, Object?> _item(
  String id,
  String type, {
  String? name,
  int quantity = 1,
  Map<String, Object?> values = const {},
  List<Object?> children = const [],
  String? parent,
}) => {
  'id': id,
  'parent_id': parent,
  'type_code': type,
  'name': name,
  'quantity': quantity,
  'values': values,
  'sort_order': 0,
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
  'children': children,
};

final _types = [
  _type('clock_dial', 'Clock dial'),
  _type('bell_group', 'Bell group'),
  _type('bell', 'Bell', parents: ['bell_group']),
  _type('bell_part', 'Bell part', parents: ['bell_group'], top: false),
];

final _defs = [
  _def('clock_dial', 'size', 'range', unit: 'mm'),
  _def('clock_dial', 'lit', 'boolean'),
  _def('bell', 'weight', 'number', unit: 'kg'),
  _def(
    'bell',
    'motion',
    'select',
    options: [
      {'label': 'Flying', 'value': 'flying'},
      {'label': 'Falling', 'value': 'falling'},
    ],
  ),
  _def('bell', 'note', 'text'),
  _def('bell', 'old', 'text', active: false),
];

List<Object?> _tree() => [
  _item(
    'g1',
    'bell_group',
    name: 'Tower bells',
    children: [
      _item(
        'b1',
        'bell',
        name: 'Big bell',
        quantity: 2,
        parent: 'g1',
        values: {'weight': 120.0, 'motion': 'flying'},
      ),
    ],
  ),
  _item(
    'd1',
    'clock_dial',
    values: {
      'size': {'min': 800, 'max': 1000},
    },
  ),
];

FakeHttp _http({
  List<String> perms = const ['opportunities.read', 'opportunities.write'],
  List<Object?>? tree,
  Object? Function(Object?)? onDelete,
  Object? Function(Object?)? onImport,
}) => FakeHttp({
  'POST /api/v1/opportunities/o1/baseline/import': ?onImport,
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/opportunities/o1/baseline': (_) => tree ?? _tree(),
  'GET /api/v1/baseline-item-types': (_) => _types,
  'GET /api/v1/attribute-definitions': (_) => _defs,
  'POST /api/v1/opportunities/o1/baseline/items': (b) => _item('new', 'bell'),
  'PUT /api/v1/opportunities/o1/baseline/items/b1': (b) => _item('b1', 'bell'),
  'DELETE /api/v1/opportunities/o1/baseline/items/b1': onDelete ?? (_) => null,
});

Future<void> _pump(
  WidgetTester tester,
  FakeHttp h, {
  CsvPicker? jsonPicker,
  Size size = const Size(1400, 2400),
  bool inDialog = false,

  /// When given, the section is shown only while this is true (to unmount it under an open dialog).
  ValueNotifier<bool>? shown,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(h)),
        if (jsonPicker != null) jsonPickerProvider.overrideWithValue(jsonPicker),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(meProvider);
              if (inDialog) {
                return TextButton(
                  onPressed: () => showSiteBaseline(context, opportunityId: 'o1'),
                  child: const Text('Open baseline'),
                );
              }
              const section = SingleChildScrollView(
                child: BaselineSection(opportunityId: 'o1'),
              );
              if (shown == null) return section;
              return ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (_, on, _) => on ? section : const SizedBox.shrink(),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (inDialog) {
    await tester.tap(find.text('Open baseline'));
    await tester.pumpAndSettle();
  }
}

Future<void> _choose(WidgetTester tester, String key, String text) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the tree with type, name, quantity and a value summary', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    expect(find.text('Site baseline'), findsOneWidget);
    expect(find.byKey(const ValueKey('baseline-item-g1')), findsOneWidget);
    expect(find.text('Bell group · Tower bells'), findsOneWidget);
    expect(find.text('Bell · Big bell'), findsOneWidget);
    expect(find.text('Qty 2'), findsOneWidget);
    // With write access each value is a chip; an empty attribute asks to be set.
    expect(find.text('L-weight 120 kg'), findsOneWidget);
    expect(find.text('L-motion Flying'), findsOneWidget);
    expect(find.text('L-note: unknown — set'), findsOneWidget);
    expect(find.text('Clock dial'), findsOneWidget);
    expect(find.text('L-size 800–1000 mm'), findsOneWidget);
    expect(find.text('L-lit: unknown — set'), findsOneWidget);
    // Definitions are requested per item type scope.
    final scopes = {
      for (final (i, r) in h.requests.indexed)
        if (r == 'GET /api/v1/attribute-definitions') h.queries[i]['scope'],
    };
    expect(scopes, containsAll(['bell', 'clock_dial']));
  });

  testWidgets('shows a hint when nothing is recorded', (tester) async {
    await _pump(tester, _http(tree: const []));
    expect(find.byKey(const ValueKey('baseline-empty')), findsOneWidget);
  });

  testWidgets('is read-only without opportunities.write', (tester) async {
    await _pump(tester, _http(perms: const ['opportunities.read']));
    expect(find.byKey(const ValueKey('baseline-item-b1')), findsOneWidget);
    expect(find.byKey(const ValueKey('baseline-add')), findsNothing);
    // Read-only keeps the plain summary line and offers no chips to tap.
    expect(find.text('L-weight 120 kg · L-motion Flying'), findsOneWidget);
    expect(find.byKey(const ValueKey('baseline-chip-b1-note')), findsNothing);
    expect(find.byKey(const ValueKey('baseline-edit-b1')), findsNothing);
    expect(find.byKey(const ValueKey('baseline-delete-b1')), findsNothing);
  });

  testWidgets('adds a top-level item with values built from its definitions', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-add')));
    await tester.pumpAndSettle();
    await _choose(tester, 'baseline-type', 'Clock dial');
    expect(find.byKey(const ValueKey('bl-attr-size-min')), findsOneWidget);
    expect(find.byKey(const ValueKey('bl-attr-weight')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('bl-attr-size-min')),
      '800',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bl-attr-size-max')),
      '1000',
    );
    await tester.enterText(
      find.byKey(const ValueKey('baseline-name')),
      'North',
    );
    await tester.tap(find.byKey(const ValueKey('baseline-save')));
    await tester.pumpAndSettle();
    expect(h.bodies['POST /api/v1/opportunities/o1/baseline/items'], {
      'type_code': 'clock_dial',
      'name': 'North',
      'quantity': 1,
      'values': {
        'size': {'min': 800, 'max': 1000},
      },
    });
  });

  testWidgets('parents are limited to items of an allowed parent type', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-add')));
    await tester.pumpAndSettle();
    await _choose(tester, 'baseline-type', 'Bell');
    await tester.tap(find.byKey(const ValueKey('baseline-parent')));
    await tester.pumpAndSettle();
    expect(find.text('Top level'), findsWidgets);
    expect(find.text('Bell group · Tower bells'), findsWidgets);
    expect(
      find.widgetWithText(DropdownMenuItem<String>, 'Clock dial'),
      findsNothing,
    );
    await tester.tap(find.text('Bell group · Tower bells').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('baseline-save')));
    await tester.pumpAndSettle();
    final body =
        h.bodies['POST /api/v1/opportunities/o1/baseline/items']
            as Map<String, Object?>;
    expect(body['parent_id'], 'g1');
    expect(body['type_code'], 'bell');
  });

  testWidgets('a type that is not allowed at the top level needs a parent', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-add')));
    await tester.pumpAndSettle();
    await _choose(tester, 'baseline-type', 'Bell part');
    await tester.tap(find.byKey(const ValueKey('baseline-save')));
    await tester.pumpAndSettle();
    expect(find.text('Choose the item to place this under.'), findsOneWidget);
    expect(
      h.requests.contains('POST /api/v1/opportunities/o1/baseline/items'),
      isFalse,
    );
  });

  testWidgets('invalid input blocks saving and is shown at the field', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-add')));
    await tester.pumpAndSettle();
    await _choose(tester, 'baseline-type', 'Bell');
    await tester.enterText(find.byKey(const ValueKey('bl-attr-weight')), 'abc');
    await tester.tap(find.byKey(const ValueKey('baseline-save')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a number.'), findsOneWidget);
    expect(
      h.requests.contains('POST /api/v1/opportunities/o1/baseline/items'),
      isFalse,
    );
  });

  testWidgets('editing prefills the values; a cleared field is left out', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-edit-b1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bl-attr-weight')))
          .controller!
          .text,
      '120',
    );
    // The type cannot change on an existing item.
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('baseline-type')),
          )
          .onChanged,
      isNull,
    );
    await tester.enterText(find.byKey(const ValueKey('bl-attr-weight')), '');
    await tester.tap(find.byKey(const ValueKey('baseline-save')));
    await tester.pumpAndSettle();
    final body =
        h.bodies['PUT /api/v1/opportunities/o1/baseline/items/b1']
            as Map<String, Object?>;
    expect(body['values'], {'motion': 'flying'});
    expect(body['parent_id'], 'g1');
    expect(body['quantity'], 2);
    expect(body.containsKey('type_code'), isFalse);
  });

  testWidgets('an empty attribute is set in place without the full dialog', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    final before = h.requests
        .where((r) => r == 'GET /api/v1/opportunities/o1/baseline')
        .length;
    await tester.tap(find.byKey(const ValueKey('baseline-chip-b1-note')));
    await tester.pumpAndSettle();
    // Only that attribute is asked for, not the type, parent or quantity.
    expect(find.byKey(const ValueKey('bl-attr-note')), findsOneWidget);
    expect(find.byKey(const ValueKey('bl-attr-weight')), findsNothing);
    expect(find.byKey(const ValueKey('baseline-type')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('bl-attr-note')),
      'cracked',
    );
    await tester.tap(find.byKey(const ValueKey('baseline-quick-save')));
    await tester.pumpAndSettle();
    final body =
        h.bodies['PUT /api/v1/opportunities/o1/baseline/items/b1']
            as Map<String, Object?>;
    // The other values, the parent and the quantity travel along unchanged.
    expect(body['values'], {
      'weight': 120.0,
      'motion': 'flying',
      'note': 'cracked',
    });
    expect(body['parent_id'], 'g1');
    expect(body['quantity'], 2);
    expect(body['name'], 'Big bell');
    final after = h.requests
        .where((r) => r == 'GET /api/v1/opportunities/o1/baseline')
        .length;
    expect(after, before + 1, reason: 'the tree is reloaded after saving');
  });

  testWidgets('a value chip edits that value; clearing it removes it', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-chip-b1-weight')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bl-attr-weight')))
          .controller!
          .text,
      '120',
    );
    await tester.enterText(find.byKey(const ValueKey('bl-attr-weight')), '');
    await tester.tap(find.byKey(const ValueKey('baseline-quick-save')));
    await tester.pumpAndSettle();
    final body =
        h.bodies['PUT /api/v1/opportunities/o1/baseline/items/b1']
            as Map<String, Object?>;
    expect(body['values'], {'motion': 'flying'});
  });

  testWidgets(
    'a yes/no attribute is set to yes or no, false counts as filled',
    (tester) async {
      final h = FakeHttp({
        ..._http().routes,
        'PUT /api/v1/opportunities/o1/baseline/items/d1': (_) =>
            _item('d1', 'clock_dial'),
      });
      await _pump(tester, h);
      await tester.tap(find.byKey(const ValueKey('baseline-chip-d1-lit')));
      await tester.pumpAndSettle();
      await _choose(tester, 'bl-attr-lit', 'No');
      await tester.tap(find.byKey(const ValueKey('baseline-quick-save')));
      await tester.pumpAndSettle();
      final body =
          h.bodies['PUT /api/v1/opportunities/o1/baseline/items/d1']
              as Map<String, Object?>;
      expect(body['values'], {
        'size': {'min': 800, 'max': 1000},
        'lit': false,
      });
    },
  );

  testWidgets('stored values without a definition stay visible, read-only', (
    tester,
  ) async {
    await _pump(
      tester,
      _http(
        tree: [
          _item(
            'b1',
            'bell',
            values: {'weight': 120.0, 'legacy_code': 'X-9'},
          ),
        ],
      ),
    );
    expect(find.byKey(const ValueKey('baseline-chip-b1-weight')), findsOneWidget);
    final undefined = find.byKey(const ValueKey('baseline-undefined-b1-legacy_code'));
    expect(undefined, findsOneWidget);
    expect(
      find.descendant(of: undefined, matching: find.text('legacy_code: X-9')),
      findsOneWidget,
    );
    expect(find.byType(ActionChip).evaluate().any((e) {
      final k = (e.widget.key as ValueKey?)?.value;
      return k == 'baseline-chip-b1-legacy_code';
    }), isFalse);
  });

  testWidgets('the quick-edit dialog cannot be popped while saving', (
    tester,
  ) async {
    final gate = Completer<void>();
    final h = FakeHttp({
      ..._http().routes,
      'PUT /api/v1/opportunities/o1/baseline/items/b1': (_) async {
        await gate.future;
        return _item('b1', 'bell');
      },
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-chip-b1-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bl-attr-note')), 'x');
    await tester.tap(find.byKey(const ValueKey('baseline-quick-save')));
    await tester.pump();
    await tester.pump();
    final nav = Navigator.of(
      tester.element(find.byKey(const ValueKey('baseline-quick-save'))),
    );
    await nav.maybePop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('baseline-quick-save')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('baseline-quick-save')), findsNothing);
  });

  testWidgets('a refused value stays in the dialog with the message', (
    tester,
  ) async {
    final h = FakeHttp({
      ..._http().routes,
      'PUT /api/v1/opportunities/o1/baseline/items/b1': (_) =>
          const FakeStatus(422, {'error': 'validation', 'message': 'nope'}),
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-chip-b1-note')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bl-attr-note')), 'x');
    await tester.tap(find.byKey(const ValueKey('baseline-quick-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bl-attr-note')), findsOneWidget);
    expect(find.textContaining('nope'), findsOneWidget);
  });

  testWidgets('deleting asks first and surfaces a refusal', (tester) async {
    final h = _http(
      onDelete: (_) => const FakeStatus(409, {
        'error': 'conflict',
        'message': 'item has children; remove them first',
      }),
    );
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('baseline-delete-b1')));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bell · Big bell?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('baseline-delete-confirm')));
    await tester.pumpAndSettle();
    expect(
      h.requests.contains('DELETE /api/v1/opportunities/o1/baseline/items/b1'),
      isTrue,
    );
    expect(find.textContaining('item has children'), findsOneWidget);
  });

  testWidgets('works with opportunities.read only and asks per type scope', (
    tester,
  ) async {
    final h = _http(perms: const ['opportunities.read']);
    await _pump(tester, h);
    expect(find.byKey(const ValueKey('baseline-item-b1')), findsOneWidget);
    expect(find.text('L-weight 120 kg · L-motion Flying'), findsOneWidget);
    final scopes = [
      for (final (i, r) in h.requests.indexed)
        if (r == 'GET /api/v1/attribute-definitions') h.queries[i]['scope'],
    ];
    expect(scopes, isNotEmpty);
    // Never unscoped and never the product scope (both need products.read).
    expect(scopes, everyElement(isIn(['bell', 'bell_group', 'clock_dial'])));
  });

  group('import from the tower configurator', () {
    const importKey = ValueKey('baseline-import-tower');
    const importPath = 'POST /api/v1/opportunities/o1/baseline/import';

    Map<String, Object?> report({bool dry = true, int replaced = 0}) => {
      'dry_run': dry,
      'source_id': 'tower_configurator',
      'replaced': replaced,
      'created': {'bell_group': 1, 'bell': 3, 'clock_dial': 0},
      'items': [],
      'warnings': [
        {
          'bell': 'bell_2',
          'field': 'motion',
          'message': 'unknown motion swirling',
        },
      ],
      'unmapped_fields': [
        {'field': 'topology', 'count': 1},
      ],
    };

    CsvPicker picks(String text) => () async =>
        (name: 'tower.json', bytes: Uint8List.fromList(utf8.encode(text)));

    List<Object?> importCalls(FakeHttp h) => [
      for (final (i, r) in h.requests.indexed)
        if (r == importPath) h.queries[i]['dry_run'],
    ];

    int baselineLoads(FakeHttp h) => h.requests
        .where((r) => r == 'GET /api/v1/opportunities/o1/baseline')
        .length;

    testWidgets('marks the items that came from an import', (tester) async {
      final tree = _tree();
      ((tree[0]! as Map<String, Object?>)['children']! as List)
          .cast<Map<String, Object?>>()
          .first['import_source'] = 'tower_configurator';
      await _pump(tester, _http(tree: tree));
      expect(find.text('Bell · Big bell · imported'), findsOneWidget);
      expect(find.text('Bell group · Tower bells'), findsOneWidget);
    });

    testWidgets('is only offered with opportunities.write', (tester) async {
      await _pump(tester, _http(perms: const ['opportunities.read']));
      expect(find.byKey(importKey), findsNothing);
    });

    testWidgets('the baseline dialog previews, imports and refreshes', (
      tester,
    ) async {
      var calls = 0;
      final h = _http(onImport: (_) => report(dry: ++calls == 1, replaced: 2));
      await _pump(tester, h, jsonPicker: picks('{"bells":[]}'), inDialog: true);
      final before = baselineLoads(h);
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      expect(importCalls(h), [true]);
      expect(h.bodies[importPath], {'bells': []});
      expect(find.text('Import preview'), findsOneWidget);
      expect(find.textContaining('1 bell group'), findsOneWidget);
      expect(find.textContaining('3 bell(s)'), findsOneWidget);
      expect(find.textContaining('replaces 2'), findsOneWidget);
      expect(find.textContaining('bell_2'), findsOneWidget);
      expect(find.textContaining('unknown motion swirling'), findsOneWidget);
      expect(find.textContaining('topology'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('baseline-import-confirm')));
      await tester.pumpAndSettle();
      expect(importCalls(h), [true, false]);
      expect(find.text('Import preview'), findsNothing);
      expect(baselineLoads(h), before + 1);
    });

    testWidgets('cancel imports nothing', (tester) async {
      final h = _http(onImport: (_) => report());
      await _pump(tester, h, jsonPicker: picks('{}'));
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('baseline-import-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('Import preview'), findsNothing);
      expect(importCalls(h), [true]);
    });

    testWidgets('a cancelled file pick does nothing', (tester) async {
      final h = _http(onImport: (_) => report());
      await _pump(tester, h, jsonPicker: () async => null);
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      expect(importCalls(h), isEmpty);
    });

    testWidgets('a file that is not JSON is refused before any call', (
      tester,
    ) async {
      final h = _http(onImport: (_) => report());
      await _pump(tester, h, jsonPicker: picks('not json'));
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      expect(find.textContaining('not valid JSON'), findsOneWidget);
      expect(importCalls(h), isEmpty);
    });

    testWidgets('shows the server message for a 422', (tester) async {
      final h = _http(
        onImport: (_) => const FakeStatus(422, {
          'error': 'validation',
          'message': 'bells must be a list',
        }),
      );
      await _pump(tester, h, jsonPicker: picks('{"bells":1}'));
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      expect(find.text('Import preview'), findsNothing);
      expect(find.textContaining('bells must be a list'), findsOneWidget);
    });

    testWidgets('cannot be dismissed while the import is running', (
      tester,
    ) async {
      final gate = Completer<void>();
      var n = 0;
      final h = _http(
        onImport: (_) {
          n++;
          if (n == 1) return report();
          return gate.future.then((_) => report(dry: false));
        },
      );
      await _pump(tester, h, jsonPicker: picks('{}'));
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('baseline-import-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Import preview'), findsOneWidget);
      final cancel = tester.widget<TextButton>(
        find.byKey(const ValueKey('baseline-import-cancel')),
      );
      expect(cancel.onPressed, isNull);
      await tester.tapAt(const Offset(5, 5)); // the barrier
      await tester.pump();
      await Navigator.of(
        tester.element(find.text('Import preview')),
      ).maybePop(); // what the system back does
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Import preview'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Import preview'), findsNothing);
    });

    testWidgets('keeps both actions reachable on a narrow screen', (
      tester,
    ) async {
      var item = _item('deep-bell', 'bell', quantity: 2);
      for (var depth = 0; depth < 7; depth++) {
        item = _item('group-$depth', 'bell_group', children: [item]);
      }
      await _pump(
        tester,
        _http(
          perms: const [
            'opportunities.read',
            'opportunities.write',
            'products.read',
          ],
          tree: [item],
        ),
        size: const Size(320, 900),
        inDialog: true,
      );
      expect(tester.takeException(), isNull, reason: 'no layout overflow');
      for (final key in [importKey, const ValueKey('baseline-add')]) {
        final r = tester.getRect(find.byKey(key));
        expect(r.left, greaterThanOrEqualTo(0), reason: '$key');
        expect(r.right, lessThanOrEqualTo(320), reason: '$key');
      }
      final edit = find.byKey(const ValueKey('baseline-edit-deep-bell'));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('Edit baseline item'), findsOneWidget);
    });

    testWidgets('says so when the file cannot be read', (tester) async {
      final h = _http(onImport: (_) => report());
      await _pump(
        tester,
        h,
        jsonPicker: () async => throw const FileSystemException('denied'),
      );
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('The file could not be read.'), findsOneWidget);
      expect(find.text('Import preview'), findsNothing);
      expect(importCalls(h), isEmpty, reason: 'nothing was sent');
    });

    testWidgets('does not touch a screen that was closed during the import', (
      tester,
    ) async {
      final gate = Completer<void>();
      var n = 0;
      final shown = ValueNotifier(true);
      final h = _http(
        onImport: (_) {
          n++;
          if (n == 1) return report();
          return gate.future.then((_) => report(dry: false));
        },
      );
      await _pump(tester, h, jsonPicker: picks('{}'), shown: shown);
      await tester.tap(find.byKey(importKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('baseline-import-confirm')));
      await tester.pump();
      shown.value = false; // the screen goes away while the import runs
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Import preview'), findsNothing);
    });
  });
}

