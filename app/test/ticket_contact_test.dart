import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _ticket() => {
  'id': 't1',
  'number': 'T2026-00009',
  'subject': 'Pump is noisy',
  'status': 'open',
  'priority': 'normal',
  'category': 'service',
  'language': 'nl',
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'contact_id': 'p1',
  'contact_name': 'Luc Claes',
  'contact_email': 'luc.claes@beta.example',
  'internal': false,
  'article_count': 3,
  'created_at': '2026-11-06T10:00:00Z',
  'updated_at': '2026-11-06T10:00:00Z',
  ...ticketExtras(),
};

Map<String, Object?> _article(
  String id,
  String kind,
  Map<String, Object?> extra,
) => {
  'id': id,
  'kind': kind,
  'from_address': '',
  'from_name': '',
  'to_addresses': <String>[],
  'cc_addresses': <String>[],
  'subject': '',
  'body': 'x',
  'attachments': <Object?>[],
  'created_at': '2026-11-06T10:00:00Z',
  ...extra,
};

void main() {
  testWidgets(
    'calls and portal messages show in the conversation; saving keeps the person',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final detail = {
        'ticket': _ticket(),
        ...detailExtras(),
        'articles': [
          _article('a1', 'portal_in', {
            'body': 'Het lekt.',
            'from_name': 'Luc Claes',
            'contact_name': 'Luc Claes',
          }),
          _article('a2', 'call_in', {
            'body': 'Called about the leak.',
            'contact_name': 'Luc Claes',
            'author_name': 'Support Agent',
            'phone_number': '+32 478 00 00 44',
            'duration_seconds': 190,
          }),
          _article('a3', 'call_out', {
            'body': 'Technician comes Thursday.',
            'author_name': 'Support Agent',
          }),
        ],
      };
      final http = FakeHttp({
        'GET /api/v1/tickets/t1': (_) => detail,
        'PUT /api/v1/tickets/t1': (_) => detail,
        'GET /api/v1/me': (_) =>
            meJson(['helpdesk.read', 'helpdesk.write', 'helpdesk.reply']),
        'GET /api/v1/users': (_) => <Object?>[],
        'GET /api/v1/quotations': (_) => {'items': <Object?>[], 'total': 0},
        'GET /api/v1/opportunities': (_) => {'items': <Object?>[], 'total': 0},
        'GET /api/v1/customers/c2/contacts': (_) => [
          contactJson(),
          contactJson(id: 'p2', first: 'Marie', last: 'Dupont', language: null),
        ],
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TicketScreen(id: 't1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Luc Claes · Via the customer portal'), findsOneWidget);
      expect(
        find.text('Incoming call · Luc Claes · Support Agent'),
        findsOneWidget,
      );
      expect(
        find.text('+32 478 00 00 44  ·  4 min'),
        findsOneWidget,
        reason: '190 s rounds up',
      );
      expect(find.text('Outgoing call · Support Agent'), findsOneWidget);
      expect(find.text('Log call'), findsOneWidget);
      // The person is shown with their language in the properties.
      expect(
        find.textContaining('Luc Claes · Technician · Nederlands'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final sent = http.bodies['PUT /api/v1/tickets/t1'] as Map;
      expect(
        sent['contact_id'],
        'p1',
        reason: 'a save must not unlink the person',
      );
      expect(sent['customer_id'], 'c2');
    },
  );
}
