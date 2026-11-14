import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/opportunities/baseline_section.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

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
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/opportunities/o1/baseline': (_) => tree ?? _tree(),
  'GET /api/v1/baseline-item-types': (_) => _types,
  'GET /api/v1/attribute-definitions': (_) => _defs,
  'POST /api/v1/opportunities/o1/baseline/items': (b) => _item('new', 'bell'),
  'PUT /api/v1/opportunities/o1/baseline/items/b1': (b) => _item('b1', 'bell'),
  'DELETE /api/v1/opportunities/o1/baseline/items/b1': onDelete ?? (_) => null,
});

Future<void> _pump(WidgetTester tester, FakeHttp h) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(h))],
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
              return const SingleChildScrollView(
                child: BaselineSection(opportunityId: 'o1'),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
    expect(find.text('L-weight 120 kg · L-motion Flying'), findsOneWidget);
    expect(find.text('Clock dial'), findsOneWidget);
    expect(find.text('L-size 800–1000 mm'), findsOneWidget);
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
}
