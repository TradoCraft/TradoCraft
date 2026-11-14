import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/features/admin/baseline_types_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _type(
  String code,
  String name, {
  List<String> parents = const [],
  bool top = true,
  bool active = true,
  int sort = 0,
}) => {
  'id': 'id-$code',
  'code': code,
  'name': name,
  'allowed_parent_codes': parents,
  'allow_top_level': top,
  'sort_order': sort,
  'active': active,
};

final _types = [
  _type('bell_group', 'Bell group'),
  _type('bell', 'Bell', parents: ['bell_group'], sort: 2),
  _type('old', 'Old type', active: false),
];

FakeHttp _http({
  List<String> perms = const ['products.write'],
  Object? Function(Object?)? onDelete,
}) => FakeHttp({
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/baseline-item-types': (_) => _types,
  'GET /api/v1/attribute-definitions': (_) => [],
  'POST /api/v1/baseline-item-types': (b) => _type('x', 'X'),
  'PUT /api/v1/baseline-item-types/id-bell': (b) => _type('bell', 'Bell'),
  'DELETE /api/v1/baseline-item-types/id-bell': onDelete ?? (_) => null,
});

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, [
  Widget page = const BaselineTypesPage(),
]) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
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
              return page;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the types with parents, top level and inactive marker', (
    tester,
  ) async {
    await _pump(tester, _http());
    expect(find.text('Bell group'), findsOneWidget);
    final bell = tester.widget<ListTile>(
      find.byKey(const ValueKey('bltype-bell')),
    );
    expect((bell.subtitle as Text).data, contains('bell · '));
    expect((bell.subtitle as Text).data, contains('bell_group'));
    final old = tester.widget<ListTile>(
      find.byKey(const ValueKey('bltype-old')),
    );
    expect((old.subtitle as Text).data, contains('inactive'));
  });

  testWidgets('creates a type with a parent chosen from the existing types', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bltype-code')),
      'bell_part',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bltype-name')),
      'Bell part',
    );
    // Neither a parent nor the top level: refused before any request.
    await tester.tap(find.byKey(const ValueKey('bltype-top')));
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least one parent type'), findsOneWidget);
    expect(h.requests, isNot(contains('POST /api/v1/baseline-item-types')));
    await tester.tap(find.byKey(const ValueKey('bltype-parent-bell')));
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    expect(h.bodies['POST /api/v1/baseline-item-types'], {
      'code': 'bell_part',
      'name': 'Bell part',
      'allowed_parent_codes': ['bell'],
      'allow_top_level': false,
      'sort_order': 0,
      'active': true,
    });
  });

  testWidgets('refuses an invalid code', (tester) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bltype-code')),
      'Bad Code',
    );
    await tester.enterText(find.byKey(const ValueKey('bltype-name')), 'X');
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('lowercase'), findsOneWidget);
    expect(h.requests, isNot(contains('POST /api/v1/baseline-item-types')));
  });

  testWidgets('editing locks the code and can deactivate', (tester) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-edit-bell')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bltype-code')))
          .enabled,
      isFalse,
    );
    // A type may list itself as an allowed parent (the server permits it), so the chip is there.
    expect(find.byKey(const ValueKey('bltype-parent-bell')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('bltype-parent-bell_group')),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const ValueKey('bltype-name')), 'Bells');
    await tester.tap(find.byKey(const ValueKey('bltype-active')));
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    final body = h.bodies['PUT /api/v1/baseline-item-types/id-bell'] as Map;
    expect(body, {
      'name': 'Bells',
      'allowed_parent_codes': ['bell_group'],
      'allow_top_level': true,
      'sort_order': 2,
      'active': false,
    });
  });

  testWidgets('delete asks first and surfaces the deactivate-instead refusal', (
    tester,
  ) async {
    const msg = 'type bell has items; deactivate it instead';
    final h = _http(
      onDelete: (_) =>
          const FakeStatus(409, {'error': 'conflict', 'message': msg}),
    );
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-del-bell')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bltype-delete-confirm')));
    await tester.pumpAndSettle();
    expect(h.requests, contains('DELETE /api/v1/baseline-item-types/id-bell'));
    expect(find.text(msg), findsOneWidget);
  });

  testWidgets('is a tab of the admin page for product writers', (tester) async {
    await _pump(tester, _http(), const AdminPage());
    await tester.tap(find.text('Baseline types'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bltype-new')), findsOneWidget);
  });

  testWidgets('the admin page has no such tab without products.write', (
    tester,
  ) async {
    await _pump(tester, _http(perms: const ['users.admin']), const AdminPage());
    expect(find.text('Baseline types'), findsNothing);
  });

  testWidgets('an existing self-parent rule stays visible and removable', (
    tester,
  ) async {
    final h = _http();
    _types[1] = _type('bell', 'Bell', parents: ['bell_group', 'bell'], sort: 2);
    addTearDown(
      () => _types[1] = _type('bell', 'Bell', parents: ['bell_group'], sort: 2),
    );
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-edit-bell')));
    await tester.pumpAndSettle();
    final chip = find.byKey(const ValueKey('bltype-parent-bell'));
    expect(tester.widget<FilterChip>(chip).selected, isTrue);
    await tester.tap(chip);
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    expect(
      (h.bodies['PUT /api/v1/baseline-item-types/id-bell']
          as Map)['allowed_parent_codes'],
      ['bell_group'],
    );
  });

  testWidgets('a new type can list itself as parent once its code is typed', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('bltype-parent-sub')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('bltype-code')), 'sub');
    await tester.enterText(find.byKey(const ValueKey('bltype-name')), 'Sub');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bltype-parent-sub')));
    await tester.tap(find.byKey(const ValueKey('bltype-top')));
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    final body = h.bodies['POST /api/v1/baseline-item-types'] as Map;
    expect(body['allowed_parent_codes'], ['sub']);
  });

  testWidgets('the reserved code product is refused before any request', (
    tester,
  ) async {
    final h = _http();
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('bltype-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('bltype-code')),
      'product',
    );
    await tester.enterText(find.byKey(const ValueKey('bltype-name')), 'P');
    await tester.tap(find.byKey(const ValueKey('bltype-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('reserved'), findsOneWidget);
    expect(h.requests, isNot(contains('POST /api/v1/baseline-item-types')));
  });

  testWidgets(
    'the dialog cannot be dismissed while saving, and the list refreshes',
    (tester) async {
      final gate = Completer<void>();
      final h = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.write']),
        'GET /api/v1/baseline-item-types': (_) => _types,
        'POST /api/v1/baseline-item-types': (b) async {
          await gate.future;
          return _type('x', 'X');
        },
      });
      await _pump(tester, h);
      await tester.tap(find.byKey(const ValueKey('bltype-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('bltype-code')), 'x');
      await tester.enterText(find.byKey(const ValueKey('bltype-name')), 'X');
      await tester.tap(find.byKey(const ValueKey('bltype-save')));
      await tester.pump();
      await tester.tapAt(const Offset(5, 5));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('bltype-save')), findsOneWidget);
      final before = h.requests
          .where((r) => r == 'GET /api/v1/baseline-item-types')
          .length;
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bltype-save')), findsNothing);
      expect(
        h.requests.where((r) => r == 'GET /api/v1/baseline-item-types').length,
        before + 1,
      );
    },
  );
}
