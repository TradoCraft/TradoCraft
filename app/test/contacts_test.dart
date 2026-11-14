import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/contacts/contacts_dialog.dart';
import 'package:tradocraft_app/features/helpdesk/call_dialogs.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Future<FakeHttp> _pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Builder(builder: (_) => home)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return http;
}

final _beta = Customer.fromJson(customerJson());

void main() {
  testWidgets(
    'a customer lists its people with language, greeting and portal access',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['customers.read', 'contacts.write']),
        'GET /api/v1/customers/c2/contacts': (_) => [
          contactJson(portal: true),
          contactJson(
            id: 'p2',
            first: 'Marie',
            last: 'Dupont',
            language: null,
            greeting: 'Bonjour Madame Dupont,',
            roles: ['sales_contact', 'purchasing'],
          ),
        ],
      });
      await _pump(tester, http, ContactsDialog(customer: _beta));

      expect(find.textContaining('Luc Claes'), findsOneWidget);
      expect(find.text('Technician'), findsWidgets);
      // Luc speaks another language than his company: marked with an asterisk, Marie is not.
      expect(find.textContaining('Nederlands *'), findsOneWidget);
      expect(find.textContaining('Français  ·'), findsOneWidget);
      expect(find.textContaining('Greeting: Dag Luc,'), findsOneWidget);
      expect(find.text('Sales contact'), findsOneWidget);
      expect(
        find.text('Customer portal'),
        findsOneWidget,
        reason: 'only Luc has access',
      );
      expect(find.text('New contact'), findsOneWidget);
    },
  );

  testWidgets(
    'a new contact is saved with the chosen language, address form and roles',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['customers.read', 'contacts.write']),
        'GET /api/v1/customers/c2/contacts': (_) => <Object?>[],
        'POST /api/v1/customers/c2/contacts': (_) => contactJson(),
      });
      await _pump(tester, http, ContactsDialog(customer: _beta), locale: 'nl');
      expect(find.text('Nog geen contactpersonen.'), findsOneWidget);

      await tester.tap(find.text('Nieuwe contactpersoon'));
      await tester.pumpAndSettle();
      // Last name is required.
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();
      expect(find.text('Verplicht'), findsOneWidget);
      expect(
        http.requests,
        isNot(contains('POST /api/v1/customers/c2/contacts')),
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Achternaam'),
        'Claes',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Voornaam'),
        'Luc',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'E-mailadressen (het eerste is het hoofdadres)',
        ),
        'luc.claes@beta.example, luc@beta.example',
      );
      await tester.tap(find.text('Technicus'));
      await tester.tap(find.text('Telefoonnummer toevoegen'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Met landcode, bv. +32 475 12 34 56',
        ),
        '0478 00 00 44',
      );
      await tester.tap(find.text('Toegang tot het klantenportaal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opslaan'));
      await tester.pumpAndSettle();

      final sent = http.bodies['POST /api/v1/customers/c2/contacts'] as Map;
      expect(sent['last_name'], 'Claes');
      expect(sent['first_name'], 'Luc');
      expect(sent['emails'], ['luc.claes@beta.example', 'luc@beta.example']);
      expect(sent['roles'], ['technical']);
      expect(sent['phones'], [
        {'label': 'work', 'number': '0478 00 00 44'},
      ]);
      expect(sent['address_form'], 'formal');
      expect(
        sent.containsKey('language'),
        isFalse,
        reason: 'same as the customer',
      );
      expect(sent['portal_access'], true);
    },
  );

  testWidgets(
    'the caller is looked up by number and the call is logged for that person',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/contacts/lookup': (_) => {
          'contacts': [contactJson()],
          'customers': <Object?>[],
        },
        'POST /api/v1/helpdesk/calls': (_) => {
          'ticket': {
            'id': 't9',
            'number': 'T2026-00009',
            'subject': 'Pump is noisy.',
            'status': 'open',
            'priority': 'normal',
            'category': 'service',
            'language': 'nl',
            'contact_id': 'p1',
            'contact_name': 'Luc Claes',
            'contact_email': 'luc.claes@beta.example',
            'internal': false,
            'article_count': 1,
            'created_at': '2026-11-06T10:00:00Z',
            'updated_at': '2026-11-06T10:00:00Z',
            ...ticketExtras(),
          },
          ...detailExtras(),
          'articles': <Object?>[],
        },
      });
      TicketDetailResult? result;
      await _pump(
        tester,
        http,
        Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final d = await showCallerLookup(context);
                result = TicketDetailResult(d?.ticket.number);
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Phone number'),
        '+32 478 00 00 44',
      );
      await tester.tap(find.text('Look up'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Luc Claes · Bêta Industrie SA'),
        findsOneWidget,
      );
      expect(find.textContaining('Greeting: Dag Luc,'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Log call'));
      await tester.pumpAndSettle();
      expect(find.text('Call with Luc Claes'), findsOneWidget);
      // A summary is required.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(http.requests, isNot(contains('POST /api/v1/helpdesk/calls')));

      await tester.enterText(
        find.widgetWithText(TextField, 'What was discussed'),
        'Pump is noisy.',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Duration (minutes)'),
        '4',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final sent = http.bodies['POST /api/v1/helpdesk/calls'] as Map;
      expect(sent['direction'], 'in');
      expect(sent['contact_id'], 'p1');
      expect(sent['phone_number'], '+32 478 00 00 44');
      expect(sent['duration_seconds'], 240);
      expect(sent['summary'], 'Pump is noisy.');
      expect(
        result?.number,
        'T2026-00009',
        reason: 'the ticket is handed back to open it',
      );
    },
  );

  testWidgets('nobody found offers to log the call for an unknown caller', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/contacts/lookup': (_) => {
        'contacts': <Object?>[],
        'customers': <Object?>[],
      },
    });
    await _pump(tester, http, const CallerLookupDialog(), locale: 'de');
    await tester.enterText(
      find.widgetWithText(TextField, 'Telefonnummer'),
      '+32 499 99 99 99',
    );
    await tester.tap(find.text('Suchen'));
    await tester.pumpAndSettle();
    expect(find.text('Niemand mit dieser Nummer gefunden.'), findsOneWidget);
    expect(find.text('Unbekannter Anrufer'), findsOneWidget);
  });
}

class TicketDetailResult {
  const TicketDetailResult(this.number);
  final String? number;
}
