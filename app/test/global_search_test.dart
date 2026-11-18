import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/shortcuts/host.dart';
import 'package:tradocraft_app/core/navigation/global_search.dart';
import 'package:tradocraft_app/core/navigation/global_search_model.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

SearchEntity _entity(
  String id,
  String permission,
  Future<List<SearchHit>> Function(String q, int limit) fetch,
) => SearchEntity(
  id: id,
  permission: permission,
  label: (_) => id,
  icon: Icons.circle,
  fetch: (api, q, n) => fetch(q, n),
);

Future<(FakeHttp, GoRouter)> _shell(
  WidgetTester tester,
  List<String> perms, {
  Map<String, Object? Function(Object?)> extra = const {},
}) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/customers': (_) => {
      'items': [customerJson()],
      'total': 1,
    },
    ...extra,
  });
  final router = GoRouter(
    initialLocation: '/customers',
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/customers', builder: (_, _) => const Text('LIST')),
          GoRoute(
            path: '/customers/:id',
            builder: (_, s) => Text('DETAIL ${s.pathParameters['id']}'),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const Text('ORDERS')),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => ShortcutsHost(child: child!),
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (http, router);
}

final _field = find.byKey(const ValueKey('global-search-field'));

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_field, text);
  await tester.pump(globalSearchDebounce + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  group('GlobalSearch', () {
    final api = TradocraftApi(fakeDio(FakeHttp({})));

    test(
      'asks only permitted entities, in parallel, and keeps the order',
      () async {
        final asked = <String>[];
        final s = GlobalSearch(
          api,
          {'a.read', 'c.read'},
          entities: [
            _entity('a', 'a.read', (q, n) async {
              asked.add('a:$q:$n');
              return [const SearchHit(title: 'A1', path: '/a/1')];
            }),
            _entity('b', 'b.read', (q, n) async {
              asked.add('b');
              return [const SearchHit(title: 'B1', path: '/b/1')];
            }),
            _entity(
              'c',
              'c.read',
              (q, n) async => [const SearchHit(title: 'C1', path: '/c/1')],
            ),
          ],
        );
        final groups = await s.search('  x ');
        expect(groups.map((g) => g.entity.id), ['a', 'c']);
        expect(asked, ['a:x:5']);
      },
    );

    test(
      'a failing entity does not break the others; empty ones are left out',
      () async {
        final s = GlobalSearch(
          api,
          {'a.read', 'b.read', 'c.read'},
          entities: [
            _entity('a', 'a.read', (q, n) async => throw StateError('boom')),
            _entity(
              'b',
              'b.read',
              (q, n) async => [const SearchHit(title: 'B1', path: '/b/1')],
            ),
            _entity('c', 'c.read', (q, n) async => []),
          ],
        );
        final groups = await s.search('x');
        expect(groups.map((g) => (g.entity.id, g.failed)), [
          ('a', true),
          ('b', false),
        ]);
      },
    );

    test('nothing is asked for a blank query or unknown permissions', () async {
      var calls = 0;
      final e = _entity('a', 'a.read', (q, n) async {
        calls++;
        return [];
      });
      expect(
        await GlobalSearch(api, {'a.read'}, entities: [e]).search(' '),
        isEmpty,
      );
      expect(await GlobalSearch(api, null, entities: [e]).search('x'), isEmpty);
      expect(calls, 0);
    });

    test('foldForSearch ignores case and accents', () {
      expect(foldForSearch('Bêta Liège'), 'beta liege');
    });
  });

  group('dialog', () {
    testWidgets('Ctrl+K opens it; Esc closes it', (tester) async {
      await _shell(tester, ['customers.read']);
      expect(_field, findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_field, findsNothing);
    });

    testWidgets('the button opens it', (tester) async {
      await _shell(tester, ['customers.read']);
      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await tester.pumpAndSettle();
      expect(_field, findsOneWidget);
      expect(find.byKey(const ValueKey('global-search-start')), findsOneWidget);
    });

    testWidgets(
      'searches permitted entities only, tolerates a failing one, Enter opens the first hit',
      (tester) async {
        final (http, router) = await _shell(
          tester,
          ['customers.read', 'orders.read'],
          // No orders route: that entity fails and must not hide the customers.
        );
        await tester.tap(find.byKey(const ValueKey('global-search-button')));
        await tester.pumpAndSettle();
        await _type(tester, 'beta');
        expect(find.text('Bêta Industrie SA'), findsOneWidget);
        expect(find.textContaining('could not be searched'), findsOneWidget);
        expect(http.requests, contains('GET /api/v1/customers'));
        expect(http.requests, contains('GET /api/v1/orders'));
        // quotations.read is missing: never asked.
        expect(http.requests, isNot(contains('GET /api/v1/quotations')));
        expect(
          http.queries.any((q) => q['q'] == 'beta' && q['limit'] == 5),
          isTrue,
        );
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, '/customers/c2');
        expect(find.text('DETAIL c2'), findsOneWidget);
        expect(_field, findsNothing);
      },
    );

    testWidgets('"Go to" lists matching sections and a click opens one', (
      tester,
    ) async {
      final (_, router) = await _shell(tester, [
        'customers.read',
        'orders.read',
      ]);
      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await tester.pumpAndSettle();
      await _type(tester, 'ord');
      expect(find.text('Go to'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Orders'));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, '/orders');
    });

    testWidgets('shows an empty state', (tester) async {
      await _shell(
        tester,
        ['customers.read'],
        extra: {
          'GET /api/v1/customers': (_) => {'items': [], 'total': 0},
        },
      );
      await tester.tap(find.byKey(const ValueKey('global-search-button')));
      await tester.pumpAndSettle();
      await _type(tester, 'zzz');
      expect(find.byKey(const ValueKey('global-search-empty')), findsOneWidget);
    });
  });
}
