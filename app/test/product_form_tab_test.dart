import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/features/tutorial/targets.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, dynamic> _productJson({
  String id = 'p-new',
  String code = 'M-100',
  String name = 'Motor 100',
}) => {
  'id': id,
  'code': code,
  'name': name,
  'description': '',
  'unit': 'pcs',
  'product_type': 'purchased',
  'vat_rate': '21',
  'vat_category': 'standard',
  'tracking': 'none',
  'non_discountable': false,
  'price_on_request': false,
  'price_is_indicative': false,
  'active': true,
  'default_production_remark': '',
  'created_at': '2026-11-23T10:00:00Z',
  'updated_at': '2026-11-23T10:00:00Z',
};

Future<ProviderContainer> _pumpProductsShell(
  WidgetTester tester,
  FakeHttp http,
) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    initialLocation: '/products',
    routes: [
      ShellRoute(
        builder: (c, s, child) =>
            AppShell(location: s.matchedLocation, child: child),
        routes: [
          GoRoute(
            path: '/products',
            builder: (c, _) => Center(
              child: FilledButton(
                onPressed: () => c.push('/products/new'),
                child: const Text('New product'),
              ),
            ),
          ),
          GoRoute(
            path: '/products/:id',
            builder: (_, s) => DetailPortal(location: s.uri.toString()),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  final c = ProviderContainer(
    overrides: [
      dioProvider.overrideWithValue(fakeDio(http)),
      kvStoreProvider.overrideWithValue(MemoryKvStore()),
    ],
  );
  addTearDown(c.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: c,
      child: MaterialApp.router(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets(
    'ProductForm opens in a non-blocking tab with tutorial target and dirty guard',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.read', 'products.write']),
        'GET /api/v1/product-families': (_) => <Object?>[],
        'GET /api/v1/packaging-categories': (_) => <Object?>[],
        'GET /api/v1/products/p-new': (_) => _productJson(),
        'POST /api/v1/products': (_) => _productJson(),
      });
      final c = await _pumpProductsShell(tester, http);

      // Open a reference tab first, then open /products/new in a second workspace tab.
      c.read(workspaceProvider.notifier).open('/products/existing');
      await tester.pumpAndSettle();
      c.read(workspaceProvider.notifier).focusHome();
      await tester.pumpAndSettle();

      // Open /products/new in a workspace tab.
      await tester.tap(find.text('New product'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(c.read(workspaceProvider).tabs.length, 2);
      final tabId = c.read(workspaceProvider).active!;
      expect(c.read(tutorialTargetsProvider)['product-form-save'], isNotNull);

      // Toggling a checkbox without typing in a TextField marks the tab dirty.
      final refreshBefore = c.read(productsRefreshProvider);
      await tester.ensureVisible(find.byKey(const ValueKey('pricing-on-request')));
      await tester.tap(find.byKey(const ValueKey('pricing-on-request')));
      await tester.pump();
      expect(c.read(workspaceProvider.notifier).isDirty(tabId), isTrue);

      // Editing a field also keeps the tab dirty and triggers the unsaved-changes dialog on close.
      await tester.ensureVisible(find.widgetWithText(TextField, 'Code'));
      await tester.enterText(find.widgetWithText(TextField, 'Code'), 'M-100');
      await tester.pump();
      expect(c.read(workspaceProvider.notifier).isDirty(tabId), isTrue);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Keep editing returns to the form.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(c.read(workspaceProvider).tabs.length, 2);

      // Fill name and save: clears dirty, bumps refresh, and closes the creation tab.
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Motor 100',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(c.read(workspaceProvider.notifier).isDirty(tabId), isFalse);
      expect(c.read(productsRefreshProvider), greaterThan(refreshBefore));
      expect(c.read(workspaceProvider).tabs.length, 1);
      expect(c.read(workspaceProvider).active, isNull);
    },
  );
}
