import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/customers/customer_form.dart';
import 'package:tradocraft_app/features/purchasing/supplier_form.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/vat_field.dart';

import 'fake_http.dart';

const _vies = {
  'state': 'valid',
  'name': 'ACME NV',
  'address': 'RUE DE LA LOI 16\n1000 BRUXELLES',
  'street': 'RUE DE LA LOI 16',
  'postal_code': '1000',
  'city': 'BRUXELLES',
};

/// A fake server whose chosen calls wait until the test lets them through, to hold requests in
/// flight while something else happens.
class _Gated implements HttpClientAdapter {
  _Gated(this.inner);
  final FakeHttp inner;
  final gates = <String, Completer<void>>{};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final gate = gates['${options.method} ${options.path}'];
    if (gate != null) await gate.future;
    return inner.fetch(options, body, cancel);
  }

  @override
  void close({bool force = false}) {}
}

/// Answers a VAT check; with `lookup=true` VIES knows the number.
Object? _vatAnswer(FakeHttp Function() http) {
  final q = http().queries.last;
  final lookup = q['lookup'] == true;
  return {
    'vat_number': q['vat_number'],
    'status': 'valid',
    'duplicates': <Object?>[],
    if (lookup) 'vies': _vies,
  };
}

Future<void> _show(WidgetTester tester, FakeHttp http, Widget child) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // A fresh dialog each time, as in the app: do not reuse the State of the previous one.
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
          body: Center(child: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String label) => tester
    .widget<TextFormField>(find.widgetWithText(TextFormField, label))
    .controller!
    .text;

List<Map<String, dynamic>> _checks(FakeHttp http, String path) => [
  for (var i = 0; i < http.requests.length; i++)
    if (http.requests[i] == 'GET $path') http.queries[i],
];

void main() {
  group('the customer form', () {
    late FakeHttp http;
    FakeHttp build(List<String> perms) => http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/price-zones': (_) => <Object?>[],
      'GET /api/v1/customers/vat-check': (_) => _vatAnswer(() => http),
    });

    testWidgets('a new customer is filled in from VIES, in the empty fields', (
      tester,
    ) async {
      build(['customers.read', 'customers.write']);
      await _show(tester, http, const CustomerForm());
      await tester.enterText(
        find.byKey(const ValueKey('customer-vat')),
        'BE0428759497',
      );
      await tester.pump(vatCheckDelay);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();

      expect(_text(tester, 'Name'), 'ACME NV');
      expect(_text(tester, 'Street'), 'RUE DE LA LOI 16');
      expect(_text(tester, 'Postal code'), '1000');
      expect(_text(tester, 'City'), 'BRUXELLES');
      expect(find.text('Empty fields filled in from VIES.'), findsOneWidget);

      // The typing check and the lookup asked with the form's country, not as an edit.
      final checks = _checks(http, '/api/v1/customers/vat-check');
      expect(checks.first['vat_number'], 'BE0428759497');
      expect(checks.first['country_code'], 'BE');
      expect(checks.first['lookup'], false);
      expect(checks.last['lookup'], true);
      expect(checks.last.containsKey('exclude_id'), isFalse);
    });

    testWidgets('an existing customer keeps what it has', (tester) async {
      build(['customers.read', 'customers.write']);
      final c = Customer.fromJson({
        ...customerJson(),
        'vat_number': 'BE0428759497',
      });
      await _show(tester, http, CustomerForm(customer: c));
      // The number of an existing customer is checked when the form opens, excluding itself.
      expect(
        _checks(http, '/api/v1/customers/vat-check').single['exclude_id'],
        'c2',
      );
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();

      expect(_text(tester, 'Name'), 'Bêta Industrie SA');
      expect(_text(tester, 'City'), 'Liège');
      // The empty ones are filled.
      expect(_text(tester, 'Street'), 'RUE DE LA LOI 16');
      expect(_text(tester, 'Postal code'), '1000');
      expect(find.text('Empty fields filled in from VIES.'), findsOneWidget);
    });

    testWidgets('there is no lookup without the right to change customers', (
      tester,
    ) async {
      build(['customers.read']);
      final c = Customer.fromJson({
        ...customerJson(),
        'vat_number': 'BE0428759497',
      });
      await _show(tester, http, CustomerForm(customer: c, readOnly: true));
      expect(find.byKey(const ValueKey('vat-lookup')), findsNothing);
      // Reading still shows what is wrong with the number.
      expect(
        find.text(
          'The format and check digits are right. This does not show that the number is registered.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('customer-vat')))
            .enabled,
        isFalse,
      );

      // A user who may read but is not in read-only mode still has no button.
      build(['customers.read']);
      await _show(tester, http, CustomerForm(customer: c));
      expect(find.byKey(const ValueKey('vat-lookup')), findsNothing);
    });

    testWidgets(
      'a lookup that answers while the form is saved changes nothing',
      (tester) async {
        build(['customers.read', 'customers.write']);
        http.routes['GET /api/v1/price-zones'] = (_) => [
          {'id': 'z1', 'code': 'Z1', 'name': 'Zone 1', 'sort_order': 1},
        ];
        http.routes['PUT /api/v1/customers/c2'] = (_) => customerJson();
        final gated = _Gated(http)
          ..gates['GET /api/v1/customers/vat-check'] = Completer<void>()
          ..gates['PUT /api/v1/customers/c2'] = Completer<void>();
        final c = Customer.fromJson({
          ...customerJson(),
          'vat_number': 'BE0428759497',
          'price_zone_id': 'z1',
          'discount_percent': '0',
          'payment_terms_days': 30,
        });
        tester.view.physicalSize = const Size(1400, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final dio = Dio(BaseOptions(baseUrl: 'http://test'))
          ..httpClientAdapter = gated;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [dioProvider.overrideWithValue(dio)],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Center(
                  child: SingleChildScrollView(
                    child: CustomerForm(customer: c),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 1));
        // Let the check that runs when the form opens through; hold the lookup that follows.
        gated.gates['GET /api/v1/customers/vat-check']!.complete();
        await tester.pumpAndSettle();
        gated.gates['GET /api/v1/customers/vat-check'] = Completer<void>();
        expect(_text(tester, 'Street'), '');

        await tester.tap(find.byKey(const ValueKey('vat-lookup')));
        await tester.pump();
        // Save while the lookup is still on its way.
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pump();
        // The lookup now answers: the form is being saved, so it must not be touched.
        gated.gates['GET /api/v1/customers/vat-check']!.complete();
        await tester.pumpAndSettle();
        expect(
          _text(tester, 'Street'),
          '',
          reason: 'what was sent is what is shown',
        );
        expect(_text(tester, 'Postal code'), '');
        expect(find.text('Empty fields filled in from VIES.'), findsNothing);
        // While saving, the number cannot be looked up again.
        expect(
          tester
              .widget<IconButton>(find.byKey(const ValueKey('vat-lookup')))
              .onPressed,
          isNull,
        );
        // Let the save finish, so that nothing is still running when the test ends.
        gated.gates['PUT /api/v1/customers/c2']!.complete();
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a History button only for those who may see the trail', (
      tester,
    ) async {
      final c = Customer.fromJson({...customerJson()});
      build(['customers.read', 'customers.write']);
      await _show(tester, http, CustomerForm(customer: c));
      expect(find.byKey(const ValueKey('record-history')), findsNothing);

      build(['customers.read', 'customers.write', 'audit.view']);
      await _show(tester, http, CustomerForm(customer: c));
      expect(find.byKey(const ValueKey('record-history')), findsOneWidget);
      // A new customer has no history yet.
      await _show(tester, http, const CustomerForm());
      expect(find.byKey(const ValueKey('record-history')), findsNothing);
    });
  });

  group('the supplier fields', () {
    late FakeHttp http;
    FakeHttp build(List<String> perms) => http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/suppliers/vat-check': (_) => _vatAnswer(() => http),
    });

    testWidgets('fill an empty name from VIES and send the supplier along', (
      tester,
    ) async {
      build(['purchasing.read', 'purchasing.write']);
      final draft = SupplierDraft(null);
      addTearDown(draft.dispose);
      await _show(
        tester,
        http,
        SizedBox(
          width: 700,
          child: SupplierFields(draft: draft, supplierId: 's1'),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('supplier-taxid')),
        'BE0428759497',
      );
      await tester.pump(vatCheckDelay);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('vat-lookup')));
      await tester.pumpAndSettle();

      expect(draft.name.text, 'ACME NV');
      final checks = _checks(http, '/api/v1/suppliers/vat-check');
      expect(checks.last['lookup'], true);
      expect(checks.last['exclude_id'], 's1');
      expect(checks.last['country_code'], 'BE');
    });

    testWidgets(
      'keep a name that is already there, and have no button without the right',
      (tester) async {
        build(['purchasing.read', 'purchasing.write']);
        final draft = SupplierDraft(null);
        addTearDown(draft.dispose);
        draft.name.text = 'My own name';
        await _show(
          tester,
          http,
          SizedBox(width: 700, child: SupplierFields(draft: draft)),
        );
        await tester.enterText(
          find.byKey(const ValueKey('supplier-taxid')),
          'BE0428759497',
        );
        await tester.pump(vatCheckDelay);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('vat-lookup')));
        await tester.pumpAndSettle();
        expect(draft.name.text, 'My own name');
        expect(find.byKey(const ValueKey('vat-vies-detail')), findsNothing);

        build(['purchasing.read']);
        final other = SupplierDraft(null);
        addTearDown(other.dispose);
        await _show(
          tester,
          http,
          SizedBox(width: 700, child: SupplierFields(draft: other)),
        );
        expect(find.byKey(const ValueKey('vat-lookup')), findsNothing);
      },
    );
  });
}
