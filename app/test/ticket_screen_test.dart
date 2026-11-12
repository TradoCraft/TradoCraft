import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _ticket({bool internal = false}) => {
  'id': 't1',
  'number': 'T2026-00007',
  'subject': 'Frage zur Lieferzeit',
  'status': 'open',
  'priority': 'normal',
  'category': internal ? 'production_question' : 'question',
  'suggested_category': 'question',
  'language': 'de',
  'customer_id': 'c3',
  'customer_name': 'Gamma Trading GmbH',
  'contact_name': 'Klaus Weber',
  'contact_email': 'klaus@gamma.example',
  'owner_user_id': 'u1',
  'owner_name': 'Sales User',
  'internal': internal,
  'article_count': 1,
  'created_at': '2026-11-05T10:00:00Z',
  'updated_at': '2026-11-05T10:00:00Z',
  ...ticketExtras(),
};

class _Fake implements HttpClientAdapter {
  _Fake({this.internal = false});
  final bool internal;
  final requests = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) async {
    final key = '${o.method} ${o.path}';
    requests.add(key);
    final Object? json = switch (key) {
      'GET /api/v1/tickets/t1' => {
        'ticket': _ticket(internal: internal),
        ...detailExtras(),
        'articles': [
          {
            'id': 'a1',
            'kind': 'email_in',
            'from_address': 'klaus@gamma.example',
            'from_name': 'Klaus Weber',
            'to_addresses': ['sales@example.com'],
            'cc_addresses': <String>[],
            'subject': 'Frage zur Lieferzeit',
            'body': 'Wie lange ist die Lieferzeit?',
            'attachments': <Object?>[],
            'created_at': '2026-11-05T10:00:00Z',
          },
        ],
      },
      'GET /api/v1/me' => {
        'user_id': 'u1',
        'email': 'sales@example.com',
        'display_name': 'Sales User',
        'roles': ['sales'],
        'permissions': [
          'helpdesk.read',
          'helpdesk.write',
          'helpdesk.reply',
          'quotations.write',
          'orders.write',
        ],
        'modules': [],
        'memberships': [],
        'company': {
          'id': 'co',
          'name': 'Demo',
          'street': '',
          'postal_code': '',
          'city': '',
          'country_code': 'BE',
          'currency': 'EUR',
          'default_language': 'nl',
          'is_primary': true,
        },
      },
      'GET /api/v1/users' => [
        {
          'id': 'u1',
          'display_name': 'Sales User',
          'email': 'sales@example.com',
          'roles': ['sales'],
        },
      ],
      'GET /api/v1/quotations' => {'items': [], 'total': 0},
      'GET /api/v1/opportunities' => {'items': [], 'total': 0},
      'GET /api/v1/prepared-answers' => [
        {
          'id': 'p1',
          'code': 'delivery-time',
          'name': 'Delivery time',
          'category': 'General',
          'active': true,
          'updated_at': '2026-11-05T10:00:00Z',
          'texts': [
            {
              'language': 'en',
              'subject': '',
              'body': 'Our delivery time is 6 to 8 weeks.',
            },
            {
              'language': 'de',
              'subject': '',
              'body': 'Unsere Lieferzeit beträgt 6 bis 8 Wochen.',
            },
          ],
        },
      ],
      'POST /api/v1/tickets/t1/prepared-answers/p1/render' => {
        'answer_id': 'p1',
        'language': 'de',
        'fallback': false,
        'subject': '',
        'body': 'Sehr geehrte(r) Klaus Weber,\nunsere Lieferzeit beträgt 6 bis 8 Wochen.',
      },
      _ => null,
    };
    if (json == null) {
      return ResponseBody.fromString(
        '{"error":"not_found","message":"$key"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(json),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<_Fake> _pump(
  WidgetTester tester, {
  required String locale,
  bool internal = false,
}) async {
  tester.view.physicalSize = const Size(1600, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = _Fake(internal: internal);
  final dio = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = fake;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TicketScreen(id: 't1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets(
    'prepared answer is filled in for the ticket and stays editable',
    (tester) async {
      final fake = await _pump(tester, locale: 'en');
      expect(find.text('Wie lange ist die Lieferzeit?'), findsOneWidget);
      expect(
        find.text('Write in Deutsch'),
        findsOneWidget,
        reason: 'the agent sees which language to write in',
      );

      await tester.tap(find.text('Insert prepared answer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delivery time'));
      await tester.pumpAndSettle();

      expect(
        fake.requests,
        contains('POST /api/v1/tickets/t1/prepared-answers/p1/render'),
      );
      final body = tester
          .widget<TextField>(find.widgetWithText(TextField, 'Message'))
          .controller!;
      expect(body.text, contains('unsere Lieferzeit beträgt 6 bis 8 Wochen'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Message'),
        '${body.text}\nGruß',
      );
      expect(body.text, endsWith('Gruß'));
    },
  );

  testWidgets(
    'the screen is translated and internal questions explain the follow-up',
    (tester) async {
      await _pump(tester, locale: 'de', internal: true);
      expect(find.text('Antwort an Kunden'), findsOneWidget);
      expect(find.text('Interne Notiz'), findsWidgets);
      expect(
        find.textContaining(
          'Interne Frage. Fragen Sie den Kunden per Antwort auf Deutsch',
        ),
        findsOneWidget,
      );
      expect(find.text('Textbaustein einfügen'), findsOneWidget);
    },
  );
}
