import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/customers/customer_form.dart';
import 'package:tradocraft_app/features/customers/customer_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _customer() => {...customerJson(), 'price_zone_id': 'z1'};

Future<void> _pump(WidgetTester t, Widget home, {double width = 1000}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(['customers.read', 'customers.write']),
    'GET /api/v1/customers/c2': (_) => _customer(),
    'PUT /api/v1/customers/c2': (_) => _customer(),
    'GET /api/v1/price-zones': (_) => [
      {'id': 'z1', 'code': 'Z1', 'name': 'Zone'},
    ],
  });
  await t.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => home),
            GoRoute(path: '/customers', builder: (_, _) => const Text('LIST')),
          ],
        ),
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Customer _c() => Customer.fromJson(_customer());

void main() {
  Finder field(String label) => find.widgetWithText(TextFormField, label);

  group('the address row', () {
    testWidgets('wraps on a narrow width, nothing overflows', (t) async {
      await _pump(
        t,
        Scaffold(
          body: SizedBox(
            width: 480,
            child: CustomerForm(customer: _c(), screen: true),
          ),
        ),
        width: 480,
      );
      expect(t.takeException(), isNull);
      for (final label in ['Postal code', 'City', 'Country']) {
        expect(field(label), findsOneWidget, reason: label);
        await t.ensureVisible(field(label));
      }
      expect(find.text('Language'), findsOneWidget);
      // Wrapped: the country moved to a second row.
      expect(
        t.getTopLeft(field('Country')).dy,
        greaterThan(t.getTopLeft(field('Postal code')).dy),
      );
    });

    testWidgets('stays one row when it fits', (t) async {
      await _pump(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 800,
              child: CustomerForm(customer: _c(), screen: true),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      final y = t.getTopLeft(field('Postal code')).dy;
      expect(t.getTopLeft(field('Country')).dy, y);
      expect(t.getTopLeft(field('Country')).dy, y);
    });
  });

  group('unsaved changes in the customer screen', () {
    Future<ValueNotifier<bool>> pumpTab(WidgetTester t) async {
      final dirty = ValueNotifier(false);
      await _pump(
        t,
        TabScope(
          id: 1,
          active: true,
          dirty: dirty,
          setTitle: (_) {},
          child: const CustomerScreen(id: 'c2'),
        ),
      );
      return dirty;
    }

    testWidgets('an edit marks the tab, a save clears it', (t) async {
      final dirty = await pumpTab(t);
      expect(dirty.value, isFalse);
      await t.enterText(field('City'), 'Namur');
      await t.pump();
      expect(dirty.value, isTrue);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(dirty.value, isFalse);
    });

    testWidgets('closing the form clears it', (t) async {
      final dirty = await pumpTab(t);
      await t.enterText(field('Name'), 'Other');
      await t.pump();
      expect(dirty.value, isTrue);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(dirty.value, isFalse);
    });
  });
}
