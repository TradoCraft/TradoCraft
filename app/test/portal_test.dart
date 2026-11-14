import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/portal/portal_pages.dart';
import 'package:tradocraft_app/portal/portal_state.dart';

import 'fake_http.dart';

Map<String, Object?> _profile({String? language, String lang = 'nl'}) => {
  'contact_id': 'p1',
  'customer_name': 'Alpha Installaties NV',
  'first_name': 'Sofie',
  'last_name': 'Maes',
  'full_name': 'Sofie Maes',
  'email': 'sofie.maes@alpha.example',
  'job_title': 'Technicus',
  'title': 'ms',
  'address_form': 'informal',
  'language': language,
  'customer_language': 'nl',
  'effective_language': lang,
  'greeting': 'Dag Sofie,',
  'roles': ['technical'],
  'scope': 'own',
};

Map<String, Object?> _ticket(String status, {String id = 't1'}) => {
  'id': id,
  'number': 'T2026-00001',
  'subject': 'Pomp lekt',
  'status': status,
  'category': 'service',
  'contact_name': 'Sofie Maes',
  'created_at': '2026-11-05T10:00:00Z',
  'updated_at': '2026-11-05T11:00:00Z',
};

Map<String, Object?> _detail(String status) => {
  'ticket': _ticket(status),
  'messages': [
    {
      'id': 'm1',
      'direction': 'incoming',
      'author_name': 'Sofie Maes',
      'body': 'De pomp lekt sinds gisteren.',
      'attachments': <Object?>[],
      'created_at': '2026-11-05T10:00:00Z',
    },
    {
      'id': 'm2',
      'direction': 'outgoing',
      'author_name': 'Support Agent',
      'body': 'We komen langs.',
      'attachments': <Object?>[],
      'created_at': '2026-11-05T11:00:00Z',
    },
  ],
};

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  String locale = 'en',
  String? token,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      portalDioProvider.overrideWithValue(fakeDio(http)),
      initialPortalTokenProvider.overrideWithValue(token),
    ],
  );
  addTearDown(container.dispose);
  container.read(portalLocaleProvider.notifier).set(Locale(locale));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) => MaterialApp(
          locale: ref.watch(portalLocaleProvider),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: home),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // The login page keeps its spinner until the router moves on, so it never "settles".
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }
  return container;
}

void main() {
  test('the login link token is read from the fragment the e-mail uses', () {
    expect(
      linkTokenFromUri(Uri.parse('https://p.example/login#token=tcl_abc123')),
      'tcl_abc123',
    );
    expect(
      linkTokenFromUri(Uri.parse('https://p.example/login?token=tcl_q')),
      'tcl_q',
    );
    expect(linkTokenFromUri(Uri.parse('https://p.example/login')), isNull);
    expect(
      linkTokenFromUri(Uri.parse('https://p.example/login#other=1')),
      isNull,
    );
    // Anything that is not a login link (e.g. a session token) is ignored.
    expect(
      linkTokenFromUri(Uri.parse('https://p.example/login#token=tcs_abc')),
      isNull,
    );
    expect(
      linkTokenFromUri(Uri.parse('https://p.example/login#token=%zz')),
      isNull,
    );
  });

  testWidgets('asking for a login link says the same whoever asks', (
    tester,
  ) async {
    final http = FakeHttp({'POST /api/v1/portal/login-links': (_) => null});
    await _pump(tester, http, const PortalLoginPage());
    expect(find.text('Customer portal'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'E-mail'),
      'sofie@alpha.example',
    );
    await tester.tap(find.text('Send login link'));
    await tester.pumpAndSettle();

    final sent = http.bodies['POST /api/v1/portal/login-links'] as Map;
    expect(sent['email'], 'sofie@alpha.example');
    expect(sent['company_id'], portalCompanyId);
    expect(find.textContaining('login link is on its way'), findsOneWidget);
  });

  testWidgets(
    'the link from the e-mail is exchanged for a session in the person\'s language',
    (tester) async {
      final http = FakeHttp({
        'POST /api/v1/portal/sessions': (_) => {
          'token': 'tcs_session',
          'expires_at': '2026-11-07T10:00:00Z',
          'profile': _profile(language: 'fr', lang: 'fr'),
        },
      });
      final c = await _pump(
        tester,
        http,
        const PortalLoginPage(linkToken: 'tcl_abc'),
        settle: false,
      );
      expect(http.bodies['POST /api/v1/portal/sessions'], {'token': 'tcl_abc'});
      expect(c.read(portalTokenProvider), 'tcs_session');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'portal_session_token',
        ),
        'tcs_session',
      );
      expect(c.read(portalLocaleProvider)?.languageCode, 'fr');
    },
  );

  testWidgets('an expired link explains itself and offers a new one', (
    tester,
  ) async {
    final http = FakeHttp({}); // the server answers 404/401 for the exchange
    final c = await _pump(
      tester,
      http,
      const PortalLoginPage(linkToken: 'tcl_old'),
      locale: 'de',
    );
    expect(c.read(portalTokenProvider), isNull);
    expect(
      find.textContaining('abgelaufen oder wurde bereits verwendet'),
      findsOneWidget,
    );
    expect(find.text('Anmeldelink senden'), findsOneWidget);
  });

  testWidgets(
    'tickets show what is waiting for the customer, in their language',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/portal/me': (_) => _profile(),
        'GET /api/v1/portal/tickets': (_) => [
          _ticket('pending_customer'),
          {..._ticket('closed', id: 't2'), 'subject': 'Oude vraag'},
          {
            ..._ticket('open', id: 't3'),
            'subject': 'Offerte',
            'contact_name': 'Jan Peeters',
          },
        ],
      });
      await _pump(
        tester,
        http,
        const PortalTicketsPage(),
        locale: 'de',
        token: 'tcs_x',
      );
      expect(find.text('Wartet auf Ihre Antwort'), findsOneWidget);
      expect(find.text('Geschlossen'), findsOneWidget);
      expect(find.text('In Bearbeitung'), findsOneWidget);
      // A colleague's ticket (scope "all tickets") shows who raised it.
      expect(find.textContaining('Erstellt von Jan Peeters'), findsOneWidget);
      expect(find.textContaining('Erstellt von Sofie Maes'), findsNothing);
    },
  );

  testWidgets('replying posts the message and refreshes the conversation', (
    tester,
  ) async {
    var posted = false;
    final http = FakeHttp({
      'GET /api/v1/portal/tickets/t1': (_) =>
          _detail(posted ? 'open' : 'closed'),
      'POST /api/v1/portal/tickets/t1/messages': (_) {
        posted = true;
        return _detail('open');
      },
      'GET /api/v1/portal/tickets': (_) => <Object?>[],
    });
    await _pump(tester, http, const PortalTicketPage(id: 't1'), token: 'tcs_x');
    expect(find.text('De pomp lekt sinds gisteren.'), findsOneWidget);
    expect(find.text('We komen langs.'), findsOneWidget);
    expect(find.text('Closed'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Your message'),
      'Het lekt nog.',
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(http.bodies['POST /api/v1/portal/tickets/t1/messages'], {
      'body': 'Het lekt nog.',
      'attachment_ids': <Object?>[],
    });
    expect(
      find.text('In progress'),
      findsOneWidget,
      reason: 'a reply reopens a closed ticket',
    );
  });

  testWidgets('the profile saves language, form of address and title', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/portal/me': (_) => _profile(),
      'PUT /api/v1/portal/me': (_) => _profile(language: 'fr', lang: 'fr'),
    });
    final c = await _pump(
      tester,
      http,
      const PortalProfilePage(),
      token: 'tcs_x',
    );
    expect(find.text('Sofie Maes'), findsOneWidget);
    expect(find.textContaining('Alpha Installaties NV'), findsOneWidget);
    expect(find.text('Same as company (Nederlands)'), findsOneWidget);
    expect(find.text('Greeting: Dag Sofie,'), findsOneWidget);

    await tester.tap(find.text('Same as company (Nederlands)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Français').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(http.bodies['PUT /api/v1/portal/me'], {
      'language': 'fr',
      'address_form': 'informal',
      'title': 'ms',
    });
    expect(
      c.read(portalLocaleProvider)?.languageCode,
      'fr',
      reason: 'the portal follows the choice',
    );
  });

  testWidgets('a new ticket needs a subject and a message', (tester) async {
    final http = FakeHttp({
      'POST /api/v1/portal/tickets': (_) => _detail('open'),
    });
    await _pump(
      tester,
      http,
      const PortalNewTicketPage(),
      locale: 'fr',
      token: 'tcs_x',
    );
    await tester.tap(find.text('Envoyer'));
    await tester.pumpAndSettle();
    expect(find.text('Obligatoire'), findsOneWidget);
    expect(http.requests, isNot(contains('POST /api/v1/portal/tickets')));
  });
}
