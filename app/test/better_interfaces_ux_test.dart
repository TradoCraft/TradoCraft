import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shortcuts/actions.dart';
import 'package:tradocraft_app/app/shortcuts/preferences_dialog.dart';
import 'package:tradocraft_app/features/products/prices_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/decimal_field.dart';

Widget _app(Widget child, {List<dynamic> overrides = const []}) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

const _product = Product(
  id: 'p1',
  code: 'P-100',
  name: 'Widget',
  description: 'A widget',
  unit: 'pcs',
  productType: 'purchased',
  vatRate: '21.00',
  tracking: 'none',
  nonDiscountable: false,
  priceOnRequest: false,
  priceIsIndicative: false,
  active: true,
  defaultProductionRemark: '',
);

const _me = Me(
  userId: 'u1',
  email: 'admin@example.com',
  displayName: 'Admin',
  company: Company(
    id: 'c1',
    name: 'Acme',
    street: 'Main 1',
    postalCode: '1000',
    city: 'Brussels',
    countryCode: 'BE',
    currency: 'EUR',
    isPrimary: true,
    defaultLanguage: 'en',
    autosaveMinutes: 5,
    quotationSingleLineItems: true,
  ),
  roles: ['admin'],
  permissions: ['prices.write', 'products.read'],
  modules: [],
  memberships: [],
);

void main() {
  tearDown(() => ShortcutBindings.setOverrides(const {}));

  group('computeZonePrice', () {
    test('multiplies and rounds to step', () {
      expect(
        computeZonePrice('100.00', multiplier: '1.15', rounding: '0.05'),
        '115.00',
      );
      expect(
        computeZonePrice('10.03', multiplier: '1.15', rounding: '0.05'),
        '11.55',
      );
      expect(
        computeZonePrice('10.00', multiplier: '1.125', rounding: 'none'),
        '11.25',
      );
      expect(computeZonePrice(null, multiplier: '1.15'), isNull);
    });
  });

  group('ShortcutBindings & preferences', () {
    test('detects conflicts including anyShift and rejects modifier-free non-cancel', () {
      const saveChord = ShortcutChord(
        LogicalKeyboardKey.keyS,
        mod: ChordMod.standard,
      );
      final conflict = ShortcutBindings.findConflict(
        ShortcutAction.find,
        saveChord,
        web: false,
      );
      expect(conflict, ShortcutAction.save);

      // help uses anyShift: true, so both Ctrl+/ and Ctrl+Shift+/ conflict with help.
      const slashNoShift = ShortcutChord(
        LogicalKeyboardKey.slash,
        mod: ChordMod.standard,
      );
      const slashWithShift = ShortcutChord(
        LogicalKeyboardKey.slash,
        mod: ChordMod.standard,
        shift: true,
      );
      expect(
        ShortcutBindings.findConflict(ShortcutAction.find, slashNoShift, web: false),
        ShortcutAction.help,
      );
      expect(
        ShortcutBindings.findConflict(ShortcutAction.find, slashWithShift, web: false),
        ShortcutAction.help,
      );

      // Modifier-free override for non-cancel action is rejected.
      applyUserShortcutPreferences(
        const UserPreferences(
          shortcuts: {
            'find': ShortcutBinding(
              key: 'keyG',
              mod: 'none',
              shift: false,
            ),
          },
        ),
      );
      expect(ShortcutBindings.overrideFor(ShortcutAction.find), isNull);

      applyUserShortcutPreferences(
        const UserPreferences(
          shortcuts: {
            'find': ShortcutBinding(
              key: 'keyG',
              mod: 'standard',
              shift: true,
            ),
          },
        ),
      );
      expect(ShortcutAction.find.describe(web: false), contains('+Shift+G'));
    });

    testWidgets('UserPreferencesDialog renders shortcuts and custom badge', (
      t,
    ) async {
      await t.pumpWidget(
        _app(
          const UserPreferencesDialog(),
          overrides: [
            userPreferencesProvider.overrideWith(
              (ref) async => const UserPreferences(
                shortcuts: {
                  'find': ShortcutBinding(
                    key: 'keyG',
                    mod: 'standard',
                    shift: true,
                  ),
                },
              ),
            ),
          ],
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(TabBar),
          matching: find.text('Shortcuts'),
        ),
        findsOneWidget,
      );
      expect(find.text('Custom'), findsOneWidget);
    });
  });

  group('Multi-zone price table', () {
    testWidgets('auto-calculates other zones from first zone and allows override', (
      t,
    ) async {
      const zones = [
        PriceZone(id: 'z1', code: 'BE', name: 'Belgium', sortOrder: 1),
        PriceZone(
          id: 'z2',
          code: 'FR',
          name: 'France',
          sortOrder: 2,
          defaultMultiplier: '1.20',
          defaultRounding: '0.05',
        ),
      ];
      await t.pumpWidget(
        _app(
          const PricesTab(product: _product),
          overrides: [
            meProvider.overrideWith((ref) async => _me),
            priceZonesProvider.overrideWith((ref) async => zones),
          ],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('New price'));
      await t.pumpAndSettle();

      // Enter 100 in first zone (BE) -> FR auto-calculates to 120,00.
      await t.enterText(find.byKey(const ValueKey('zone-price-BE')), '100');
      await t.pumpAndSettle();
      final frField = t.widget<DecimalField>(
        find.byKey(const ValueKey('zone-price-FR')),
      );
      expect(frField.controller.text, '120');

      // Manual override on FR marks it overridden and shows reset button.
      await t.enterText(find.byKey(const ValueKey('zone-price-FR')), '130');
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('zone-reset-FR')), findsOneWidget);

      // Changing BE's base price to 200 keeps FR's manual override at 130.
      await t.enterText(find.byKey(const ValueKey('zone-price-BE')), '200');
      await t.pumpAndSettle();
      expect(frField.controller.text, '130');

      // Resetting FR restores 240 (200 * 1.20).
      await t.tap(find.byKey(const ValueKey('zone-reset-FR')));
      await t.pumpAndSettle();
      expect(frField.controller.text, '240');
    });
  });
}
