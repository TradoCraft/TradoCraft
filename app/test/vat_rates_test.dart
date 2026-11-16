import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/features/admin/vat_rates_page.dart';
import 'package:tradocraft_app/features/customers/customer_form.dart';
import 'package:tradocraft_app/features/opportunities/opportunity_form.dart';
import 'package:tradocraft_app/features/products/product_form.dart';
import 'package:tradocraft_app/features/quotations/quotation_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/vat_field.dart';

import 'fake_http.dart';

Map<String, Object?> _meForCountry(
  String countryCode,
  List<String> perms,
) => {
  ...meJson(perms),
  'company': {
    ...(meJson(perms)['company']! as Map<String, Object?>),
    'country_code': countryCode,
  },
};

Map<String, Object?> _vatRuleJson({
  required String id,
  required String countryCode,
  required String category,
  required String rate,
  int? minBuildingAgeYears,
  String startDate = '2020-01-01',
  String? endDate,
  String notes = '',
}) => {
  'id': id,
  'country_code': countryCode,
  'category': category,
  'rate': rate,
  'min_building_age_years': ?minBuildingAgeYears,
  'start_date': startDate,
  'end_date': ?endDate,
  'notes': notes,
  'updated_at': '2026-01-01T00:00:00Z',
};

Future<void> _pumpHost(
  WidgetTester tester,
  FakeHttp http,
  Widget child,
) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox());
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
              return child;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('VAT regime & rate helpers', () {
    test('deriveDefaultVatRegime mirrors backend rules', () {
      expect(
        deriveDefaultVatRegime(
          companyCountry: 'BE',
          customerCountry: 'BE',
          vatNumber: null,
        ),
        'domestic',
      );
      expect(
        deriveDefaultVatRegime(
          companyCountry: 'BE',
          customerCountry: 'NL',
          vatNumber: 'NL123456789B01',
        ),
        'intra_eu',
      );
      expect(
        deriveDefaultVatRegime(
          companyCountry: 'BE',
          customerCountry: 'NL',
          vatNumber: '',
        ),
        'domestic',
      );
      expect(
        deriveDefaultVatRegime(
          companyCountry: 'BE',
          customerCountry: 'XI',
          vatNumber: 'XI123456789',
        ),
        'intra_eu',
      );
      expect(
        deriveDefaultVatRegime(
          companyCountry: 'BE',
          customerCountry: 'US',
          vatNumber: '12-3456789',
        ),
        'outside_eu',
      );
      expect(
        deriveDefaultVatRegime(
          companyCountry: 'CH',
          customerCountry: 'BE',
          vatNumber: 'BE0428759497',
        ),
        'outside_eu',
      );
    });

    test('resolveCountryCategoryRate respects dates and fallbacks', () {
      final rules = [
        CountryVatRate.fromJson(
          _vatRuleJson(
            id: 'r-old',
            countryCode: 'CH',
            category: 'standard',
            rate: '7.70',
            startDate: '2018-01-01',
            endDate: '2023-12-31',
          ),
        ),
        CountryVatRate.fromJson(
          _vatRuleJson(
            id: 'r-new',
            countryCode: 'CH',
            category: 'standard',
            rate: '8.10',
            startDate: '2024-01-01',
          ),
        ),
        CountryVatRate.fromJson(
          _vatRuleJson(
            id: 'fr-std',
            countryCode: 'FR',
            category: 'standard',
            rate: '20.00',
          ),
        ),
        CountryVatRate.fromJson(
          _vatRuleJson(
            id: 'fr-red',
            countryCode: 'FR',
            category: 'reduced',
            rate: '5.50',
          ),
        ),
      ];

      expect(
        resolveCountryCategoryRate(
          rules,
          countryCode: 'CH',
          category: 'standard',
          asOf: DateTime.utc(2023, 6, 15),
        ),
        '7.70',
      );
      expect(
        resolveCountryCategoryRate(
          rules,
          countryCode: 'CH',
          category: 'standard',
          asOf: DateTime.utc(2026, 5, 1),
        ),
        '8.10',
      );
      // Reduced without reduced rule falls back to standard.
      expect(
        resolveCountryCategoryRate(
          rules,
          countryCode: 'CH',
          category: 'reduced',
          asOf: DateTime.utc(2026, 5, 1),
        ),
        '8.10',
      );
      // Zero without rule returns '0'.
      expect(
        resolveCountryCategoryRate(
          rules,
          countryCode: 'CH',
          category: 'zero',
          asOf: DateTime.utc(2026, 5, 1),
        ),
        '0',
      );
      expect(
        resolveCountryCategoryRate(
          rules,
          countryCode: 'FR',
          category: 'reduced',
          asOf: DateTime.utc(2026, 5, 1),
        ),
        '5.50',
      );
    });
  });

  group('Admin VAT rates tab and page', () {
    testWidgets('VAT rates tab is shown to admins only', (tester) async {
      final adminHttp = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['users.admin']),
        'GET /api/v1/admin/users': (_) => <Object?>[],
        'GET /api/v1/admin/modules': (_) => <Object?>[],
        'GET /api/v1/roles': (_) => <Object?>[],
        'GET /api/v1/price-zones': (_) => <Object?>[],
        'GET /api/v1/vat-rates': (_) => <Object?>[],
      });
      await _pumpHost(tester, adminHttp, const AdminPage());
      expect(find.text('VAT rates'), findsOneWidget);

      final priceHttp = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['prices.write']),
        'GET /api/v1/price-zones': (_) => <Object?>[],
      });
      await _pumpHost(tester, priceHttp, const AdminPage());
      expect(find.text('VAT rates'), findsNothing);
    });

    testWidgets('lists, creates with 409 error, and deletes rules', (
      tester,
    ) async {
      final rules = [
        _vatRuleJson(
          id: 'vr-be',
          countryCode: 'BE',
          category: 'standard',
          rate: '21.00',
          notes: 'Standard BE',
        ),
        _vatRuleJson(
          id: 'vr-nl',
          countryCode: 'NL',
          category: 'standard',
          rate: '21.00',
        ),
      ];
      var returnConflict = true;
      final http = FakeHttp({
        'GET /api/v1/me': (_) => _meForCountry('BE', ['users.admin']),
        'GET /api/v1/vat-rates': (_) => rules,
        'POST /api/v1/admin/vat-rates': (body) {
          if (returnConflict) {
            return const FakeStatus(409, {
              'error': 'conflict',
              'message': 'Dates overlap an existing rule',
            });
          }
          final map = body! as Map<String, Object?>;
          final created = _vatRuleJson(
            id: 'vr-be-2',
            countryCode: map['country_code']! as String,
            category: map['category']! as String,
            rate: map['rate']! as String,
            startDate: (map['start_date']! as String).split('T').first,
          );
          rules.add(created);
          return created;
        },
        'DELETE /api/v1/admin/vat-rates/vr-be': (_) {
          rules.removeWhere((r) => r['id'] == 'vr-be');
          return null;
        },
      });

      await _pumpHost(
        tester,
        http,
        const SizedBox(height: 900, child: VatRatesPage()),
      );

      // Filtered to company country BE by default; NL is hidden until All is chosen.
      expect(find.byKey(const ValueKey('vat-rate-vr-be')), findsOneWidget);
      expect(find.byKey(const ValueKey('vat-rate-vr-nl')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('vat-rate-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Rate (%)'),
        '12',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // 409 error is surfaced inside the dialog without closing it.
      expect(find.text('Dates overlap an existing rule'), findsOneWidget);
      expect(
        (http.bodies['POST /api/v1/admin/vat-rates']!
            as Map<String, Object?>)['close_previous'],
        isTrue,
      );

      returnConflict = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('vat-rate-vr-be-2')), findsOneWidget);

      // Delete first rule via confirmation dialog.
      await tester.tap(find.byTooltip('Delete').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/admin/vat-rates/vr-be'));
      expect(find.byKey(const ValueKey('vat-rate-vr-be')), findsNothing);
    });
  });

  group('ProductForm VAT category and override', () {
    testWidgets('resolves company default rate and sends category/override', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => _meForCountry('FR', ['products.write']),
        'GET /api/v1/vat-rates': (_) => [
          _vatRuleJson(
            id: 'fr-std',
            countryCode: 'FR',
            category: 'standard',
            rate: '20.00',
          ),
          _vatRuleJson(
            id: 'fr-red',
            countryCode: 'FR',
            category: 'reduced',
            rate: '5.50',
          ),
        ],
        'GET /api/v1/packaging-categories': (_) => <Object?>[],
        'GET /api/v1/product-families': (_) => <Object?>[],
        'POST /api/v1/products': (body) => {
          'id': 'p99',
          'code': 'SOL-FR',
          'name': 'French Panel',
          'description': '',
          'unit': 'pcs',
          'product_type': 'purchased',
          'tracking': 'none',
          'pricing_type': 'list',
          'vat_category': 'reduced',
          'vat_rate': '10.00',
          'vat_rate_override': '10.00',
          'active': true,
        },
      });

      await _pumpHost(tester, http, const ProductForm());

      // Company is FR -> resolves 20 % automatically instead of hardcoded 21 %.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('product-resolved-vat')),
          matching: find.text('20 %'),
        ),
        findsOneWidget,
      );

      // Switching category to Reduced updates preview badge to 5,5 %.
      await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Standard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reduced').last);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('product-resolved-vat')),
          matching: find.text('5,5 %'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Code'),
        'SOL-FR',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'French Panel',
      );
      await tester.enterText(
        find.byKey(const ValueKey('product-vat-override')),
        '10',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('product-resolved-vat')),
          matching: find.text('10 %'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final sent = http.bodies['POST /api/v1/products']! as Map<String, Object?>;
      expect(sent['vat_category'], 'reduced');
      expect(sent['vat_rate_override'], '10');
      expect(sent['vat_rate'], '10');
    });
  });

  group('CustomerForm VAT regime auto-derivation', () {
    testWidgets('auto-derives regime on new customer until changed manually', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => _meForCountry('BE', ['customers.write']),
        'GET /api/v1/price-zones': (_) => <Object?>[],
        'GET /api/v1/customers/vat-check': (_) => {
          'vat_number': 'NL123456789B01',
          'status': 'format_ok',
          'duplicates': <Object?>[],
        },
      });

      await _pumpHost(tester, http, const CustomerForm());

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Country'),
        'NL',
      );
      await tester.enterText(
        find.byKey(const ValueKey('customer-vat')),
        'NL123456789B01',
      );
      await tester.pump(vatCheckDelay);
      await tester.pumpAndSettle();
      expect(find.text('EU business, VAT reverse-charged'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Country'),
        'US',
      );
      await tester.pumpAndSettle();
      expect(find.text('Outside the EU, no VAT'), findsOneWidget);

      // Manually pick Domestic reverse charge (construction).
      await tester.tap(find.byKey(const ValueKey('vat-regime-outside_eu')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Domestic reverse charge (construction)').last,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Domestic reverse charge (construction)'),
        findsOneWidget,
      );

      // Subsequent country changes preserve the manual choice.
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Country'),
        'DE',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Domestic reverse charge (construction)'),
        findsOneWidget,
      );
    });
  });

  group('Opportunity & Quotation VAT controls', () {
    testWidgets('OpportunityForm validates and saves building year', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => _meForCountry('BE', ['opportunities.write']),
        'GET /api/v1/customers': (_) => {
          'items': [customerJson()],
          'total': 1,
        },
        'GET /api/v1/power-grids': (_) => <Object?>[],
        'POST /api/v1/opportunities': (body) => {
          'id': 'opp1',
          'number': 'OPP-1',
          'title': 'Renovation',
          'stage': 'qualification',
          'customer_id': 'c2',
          'customer_name': 'Bêta Industrie SA',
          'expected_value': '1000',
          'probability': 50,
          'notes': '',
          'building_construction_year': 1995,
          'owner_name': 'Sales',
          'owner_user_id': 'u',
          'created_at': '2026-11-01T10:00:00Z',
          'updated_at': '2026-11-01T10:00:00Z',
        },
      });

      await _pumpHost(tester, http, const OpportunityForm());
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Renovation',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Customer'),
        'beta',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('C0002 · Bêta Industrie SA').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('opportunity-building-year')),
        '500',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a year between 800 and 2200'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('opportunity-building-year')),
        '1995',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final sent =
          http.bodies['POST /api/v1/opportunities']! as Map<String, Object?>;
      expect(sent['building_construction_year'], 1995);
    });

    testWidgets(
      'QuotationScreen inherits building year, sends overrides, and renders reverse charge notice',
      (tester) async {
        String previewRegime = 'domestic';
        final http = FakeHttp({
          'GET /api/v1/me': (_) => _meForCountry('BE', [
            'quotations.read',
            'quotations.write',
          ]),
          'GET /api/v1/quotations/q1': (_) => {
            'id': 'q1',
            'company_id': 'co',
            'number': 'Q2026-00001',
            'revision': 1,
            'status': 'draft',
            'customer_id': 'c1',
            'customer_name': 'Alpha Installaties NV',
            'customer_vat_number': 'BE0428759497',
            'vat_regime': 'domestic',
            'customer_street': 'Havenlaan 10',
            'customer_postal_code': '2000',
            'customer_city': 'Antwerpen',
            'customer_country_code': 'BE',
            'customer_language': 'nl',
            'price_zone_code': 'Z2',
            'customer_discount_percent': '5',
            'currency': 'EUR',
            'quote_date': '2026-11-05',
            'purpose': 'installation',
            'shipping_status': 'not_required',
            'price_date': '2026-11-05',
            'valid_until': '2026-12-05',
            'notes': '',
            'subtotal': '3686.00',
            'vat_total': '774.06',
            'total': '4460.06',
            'supersedes_id': null,
            'created_by': 'u',
            'created_at': '2026-11-05T10:00:00Z',
            'updated_at': '2026-11-05T10:00:00Z',
            'sent_at': null,
            'lines': [
              {
                'position': 1,
                'product_id': 'p1',
                'product_code': 'UNIT-100',
                'description': 'Process unit 100',
                'unit': 'pcs',
                'quantity': '1',
                'list_unit_price': '3880.0000',
                'line_discount_percent': '0',
                'pricing_type': 'list',
                'rebate_percent': '5',
                'rebate_source': 'general',
                'price_confirmed': true,
                'net_unit_price': '3686.0000',
                'line_total': '3686.00',
                'vat_rate': '21',
                'production_remark': '',
                'customer_remark': '',
              },
            ],
            'warnings': <Object?>[],
            'suggestions': <Object?>[],
            'vat_groups': [
              {'vat_rate': '21', 'base': '3686.00', 'vat': '774.06'},
            ],
          },
          'GET /api/v1/customers/c1': (_) => {
            'id': 'c1',
            'code': 'C0001',
            'name': 'Alpha Installaties NV',
            'vat_regime': 'domestic',
            'street': 'Havenlaan 10',
            'postal_code': '2000',
            'city': 'Antwerpen',
            'country_code': 'BE',
            'language': 'nl',
            'active': true,
            'price_zone_id': 'z2',
            'price_zone_code': 'Z2',
            'discount_percent': '5',
            'payment_terms_days': 30,
          },
          'GET /api/v1/products/p1': (_) => {
            'id': 'p1',
            'code': 'UNIT-100',
            'name': 'Process unit 100',
            'description': '',
            'unit': 'pcs',
            'product_type': 'manufactured',
            'tracking': 'serial',
            'pricing_type': 'list',
            'vat_rate': '21',
            'active': true,
          },
          'GET /api/v1/opportunities': (_) => {
            'items': [
              {
                'id': 'opp1',
                'number': 'OPP-1',
                'title': 'Old hall renovation',
                'stage': 'proposal',
                'customer_id': 'c1',
                'customer_name': 'Alpha Installaties NV',
                'expected_value': '1000',
                'probability': 50,
                'notes': '',
                'building_construction_year': 1995,
                'owner_name': 'Sales',
                'owner_user_id': 'u',
                'created_at': '2026-11-01T10:00:00Z',
                'updated_at': '2026-11-01T10:00:00Z',
              },
            ],
            'total': 1,
          },
          'GET /api/v1/power-grids': (_) => <Object?>[],
          'POST /api/v1/pricing/preview': (_) => {
            'price_zone_code': 'Z2',
            'customer_discount_percent': '5',
            'quote_date': '2026-11-05',
            'price_date': '2026-11-05',
            'unconfirmed_lines': 0,
            'vat_regime': previewRegime,
            'building_construction_year': 1995,
            'warnings': <Object?>[],
            'suggestions': <Object?>[],
            'lines': [
              {
                'position': 1,
                'product_id': 'p1',
                'product_code': 'UNIT-100',
                'description': 'Process unit 100',
                'unit': 'pcs',
                'quantity': '1',
                'list_unit_price': '3880.0000',
                'line_discount_percent': '0',
                'pricing_type': 'list',
                'rebate_percent': '5',
                'rebate_source': 'general',
                'price_confirmed': true,
                'net_unit_price': '3686.0000',
                'line_total': '3686.00',
                'vat_rate': previewRegime == 'domestic_reverse_charge'
                    ? '0'
                    : '21',
              },
            ],
            'vat_groups': previewRegime == 'domestic_reverse_charge'
                ? <Object?>[]
                : [
                    {'vat_rate': '21', 'base': '3686.00', 'vat': '774.06'},
                  ],
            'subtotal': '3686.00',
            'vat_total':
                previewRegime == 'domestic_reverse_charge' ? '0.00' : '774.06',
            'total': previewRegime == 'domestic_reverse_charge'
                ? '3686.00'
                : '4460.06',
          },
        });

        await _pumpHost(tester, http, const QuotationScreen(id: 'q1'));

        // Picking opp1 inherits building_construction_year 1995 and refreshes preview.
        await tester.tap(find.byKey(const ValueKey('opp-c1-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining('OPP-1').last);
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('buildingConstructionYear')),
              )
              .controller!
              .text,
          '1995',
        );
        var previewBody =
            http.bodies['POST /api/v1/pricing/preview']!
                as Map<String, Object?>;
        expect(previewBody['opportunity_id'], 'opp1');
        expect(previewBody['building_construction_year'], 1995);

        // Overriding VAT regime to domestic_reverse_charge renders the notice.
        previewRegime = 'domestic_reverse_charge';
        await tester.tap(find.byKey(const ValueKey('vat-regime-override')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Domestic reverse charge (construction)').last,
        );
        await tester.pumpAndSettle();

        previewBody =
            http.bodies['POST /api/v1/pricing/preview']!
                as Map<String, Object?>;
        expect(previewBody['vat_regime_override'], 'domestic_reverse_charge');
        expect(
          find.text('VAT reverse charge — work on immovable property'),
          findsOneWidget,
        );

        // Switching purpose to stock hides the building construction year input.
        await tester.tap(find.text('Stock').last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('buildingConstructionYear')),
          findsNothing,
        );
      },
    );
  });
}
