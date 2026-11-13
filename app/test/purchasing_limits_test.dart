import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/purchasing/purchasing_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _limits({String? purchaser}) => {
  'currency': 'EUR',
  'roles': [
    {'role': 'purchaser', 'max_amount': purchaser},
  ],
  'your_limit': null,
};

Future<void> _page(WidgetTester tester, FakeHttp http) async {
  tester.view.physicalSize = const Size(1400, 1600);
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
        home: const Scaffold(body: PurchasingPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object? Function(Object?)> _base(List<String> perms) => {
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/suppliers': (_) => [],
};

Future<void> _openLimits(WidgetTester tester) async {
  await tester.tap(find.text('Approval limits'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the segment is only for administrators of users', (
    tester,
  ) async {
    await _page(tester, FakeHttp(_base(['purchasing.read'])));
    expect(find.text('Approval limits'), findsNothing);
  });

  testWidgets('shows each role with its limit and saves a change', (
    tester,
  ) async {
    var current = _limits(purchaser: '5000.00');
    final http = FakeHttp({
      ..._base(['purchasing.read', 'users.admin']),
      'GET /api/v1/purchasing/approval-limits': (_) => current,
      'PUT /api/v1/purchasing/approval-limits': (_) =>
          current = _limits(purchaser: '7500.00'),
    });
    await _page(tester, http);
    await _openLimits(tester);
    final field = find.byKey(const ValueKey('limit-purchaser'));
    expect(tester.widget<TextField>(field).controller!.text, isNotEmpty);
    expect(find.textContaining('excluding VAT'), findsOneWidget);

    await tester.enterText(field, '7500');
    await tester.tap(find.byKey(const ValueKey('limits-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/purchasing/approval-limits']! as Map;
    expect(body['limits'], [
      {'role': 'purchaser', 'max_amount': '7500'},
    ]);
    expect(find.text('Limits saved'), findsOneWidget);
  });

  testWidgets('an empty field removes the limit', (tester) async {
    final http = FakeHttp({
      ..._base(['purchasing.read', 'users.admin']),
      'GET /api/v1/purchasing/approval-limits': (_) =>
          _limits(purchaser: '5000.00'),
      'PUT /api/v1/purchasing/approval-limits': (_) => _limits(),
    });
    await _page(tester, http);
    await _openLimits(tester);
    await tester.enterText(find.byKey(const ValueKey('limit-purchaser')), '');
    await tester.tap(find.byKey(const ValueKey('limits-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['PUT /api/v1/purchasing/approval-limits']! as Map;
    expect(body['limits'], [
      {'role': 'purchaser'},
    ]);
  });

  testWidgets('an invalid amount is refused before anything is sent', (
    tester,
  ) async {
    final http = FakeHttp({
      ..._base(['purchasing.read', 'users.admin']),
      'GET /api/v1/purchasing/approval-limits': (_) => _limits(),
    });
    await _page(tester, http);
    await _openLimits(tester);
    await tester.enterText(
      find.byKey(const ValueKey('limit-purchaser')),
      'lots',
    );
    await tester.tap(find.byKey(const ValueKey('limits-save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('limits-error')), findsOneWidget);
    expect(
      http.requests,
      isNot(contains('PUT /api/v1/purchasing/approval-limits')),
    );
  });

  testWidgets('a server refusal is shown and the form stays', (tester) async {
    final http = FakeHttp({
      ..._base(['purchasing.read', 'users.admin']),
      'GET /api/v1/purchasing/approval-limits': (_) => _limits(),
      'PUT /api/v1/purchasing/approval-limits': (_) => const FakeStatus(422, {
        'error': 'validation',
        'message': 'a limit must be 0 or more with at most 2 decimals',
      }),
    });
    await _page(tester, http);
    await _openLimits(tester);
    await tester.enterText(
      find.byKey(const ValueKey('limit-purchaser')),
      '1.005',
    );
    await tester.tap(find.byKey(const ValueKey('limits-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('at most 2 decimals'), findsOneWidget);
    expect(find.byKey(const ValueKey('limit-purchaser')), findsOneWidget);
  });
}
