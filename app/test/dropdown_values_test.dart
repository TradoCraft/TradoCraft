import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/customers/customer_form.dart';
import 'package:tradocraft_app/features/repairs/repairs_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Future<FakeHttp> _pump(
  WidgetTester t,
  Widget home,
  Map<String, Object? Function(Object?)> routes,
) async {
  t.view.physicalSize = const Size(1200, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final http = FakeHttp(routes);
  await t.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: SingleChildScrollView(child: home)),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await t.pump(const Duration(milliseconds: 10));
  }
  await t.pumpAndSettle();
  return http;
}

void main() {
  final customer = Customer.fromJson({
      ...customerJson(),
      'price_zone_id': 'z9',
      'price_zone_code': 'Z9',
    });

  group('new repair dialog contact', () {
    Future<FakeHttp> pumpRepair(
      WidgetTester t,
      Object? Function(Object?) contact,
    ) => _pump(
      t,
      NewRepairDialog(customer: customer, contactId: 'p1'),
      {
        'GET /api/v1/customers/c2/contacts': (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return [contactJson(id: 'p2', first: 'Ann', last: 'Other')];
        },
        'GET /api/v1/contacts/p1': contact,
      },
    );

    testWidgets('a preselected contact missing from the list is fetched and kept', (
      t,
    ) async {
      final http = await pumpRepair(
        t,
        (_) => contactJson(id: 'p1', first: 'Luc', last: 'Claes'),
      );
      expect(t.takeException(), isNull);
      expect(http.requests, contains('GET /api/v1/contacts/p1'));
      expect(find.text('Luc Claes'), findsOneWidget);
    });

    testWidgets('a contact of another customer is dropped, nothing crashes', (
      t,
    ) async {
      await pumpRepair(
        t,
        (_) => contactJson(id: 'p1', customerId: 'other'),
      );
      expect(t.takeException(), isNull);
      expect(find.text('Luc Claes'), findsNothing);
    });

    testWidgets('a 404 contact is dropped, nothing crashes', (t) async {
      await pumpRepair(
        t,
        (_) => const FakeStatus(404, {'error': 'not_found', 'message': 'x'}),
      );
      expect(t.takeException(), isNull);
    });
  });

  testWidgets('customer form keeps a stored price zone missing from the zone list', (
    t,
  ) async {
    await _pump(t, CustomerForm(customer: customer, screen: true), {
      'GET /api/v1/price-zones': (_) => [
        {'id': 'z1', 'code': 'Z1', 'name': 'Zone', 'sort_order': 1},
      ],
    });
    expect(t.takeException(), isNull);
    expect(find.textContaining('Z9'), findsWidgets);
  });
}
