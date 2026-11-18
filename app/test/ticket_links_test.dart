import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_links.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _linked(
  String id,
  String number, {
  String status = 'open',
  bool merged = false,
}) => {
  'link_id': 'l-$id',
  'ticket_id': id,
  'number': number,
  'subject': 'Subject $number',
  'status': status,
  'priority': 'normal',
  'customer_name': 'Customer $number',
  'owner_name': 'Agent',
  'merged': merged,
  'updated_at': '2026-11-09T09:00:00Z',
};

Map<String, Object?> _links({
  Map<String, Object?>? parent,
  List<Map<String, Object?>> children = const [],
  List<Map<String, Object?>> related = const [],
}) => {
  'parent': parent,
  'children': children,
  'related': related,
  'duplicate_of': null,
  'duplicates': <Object?>[],
};

Map<String, Object?> _ticket(String id, String number) => {
  'id': id,
  'number': number,
  'subject': 'Pick $number',
  'status': 'open',
  'priority': 'normal',
  'category': 'service',
  'language': 'en',
  'customer_name': 'Alpha NV',
  'contact_name': 'Anna',
  'contact_email': 'anna@alpha.example',
  'internal': false,
  'article_count': 1,
  'created_at': '2026-11-09T09:00:00Z',
  'updated_at': '2026-11-09T09:00:00Z',
  ...ticketExtras(),
};

Map<String, Object?> _item(
  String id,
  String number,
  String outcome, {
  String? reason,
  String? recipient,
}) => {
  'ticket_id': id,
  'number': number,
  'subject': 'Subject $number',
  'outcome': outcome,
  'reason': reason,
  'recipient': recipient,
};

Future<FakeHttp> _open(
  WidgetTester tester, {
  required Map<String, Object?> links,
  Map<String, Object? Function(Object?)> extra = const {},
  List<String> perms = const [
    'helpdesk.read',
    'helpdesk.write',
    'helpdesk.reply',
  ],
  String locale = 'en',
  double width = 1000,
}) async {
  final http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(perms),
    'GET /api/v1/tickets/t1/links': (_) => links,
    ...extra,
  });
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const SingleChildScrollView(
                child: TicketLinksCard(
                  ticketId: 't1',
                  number: 'T2026-00001',
                  canWrite: true,
                  canReply: true,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return http;
}

void main() {
  testWidgets('shows the bundle with how many members are still open', (
    tester,
  ) async {
    await _open(
      tester,
      links: _links(
        children: [
          _linked('c1', 'T2026-00002'),
          _linked('c2', 'T2026-00003', status: 'closed'),
          _linked('c3', 'T2026-00004', merged: true),
        ],
        related: [_linked('r1', 'T2026-00009')],
      ),
    );
    expect(find.text('Bundle · 1 of 3 still open'), findsOneWidget);
    expect(find.text('T2026-00002 · Subject T2026-00002'), findsOneWidget);
    expect(find.text('Related'), findsOneWidget);
    expect(find.textContaining('Merged'), findsOneWidget);
    expect(find.byKey(const ValueKey('bundle-update')), findsOneWidget);
  });

  testWidgets('a child shows its parent and has no bundle update', (
    tester,
  ) async {
    await _open(tester, links: _links(parent: _linked('p1', 'T2026-00010')));
    expect(find.text('Part of the bundle of'), findsOneWidget);
    expect(find.byKey(const ValueKey('bundle-update')), findsNothing);
  });

  testWidgets('removing a link asks the server and shows the new state', (
    tester,
  ) async {
    final http = await _open(
      tester,
      links: _links(related: [_linked('r1', 'T2026-00009')]),
      extra: {'DELETE /api/v1/tickets/t1/links/l-r1': (_) => _links()},
    );
    await tester.tap(find.byKey(const ValueKey('unlink-r1')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/tickets/t1/links/l-r1'));
    expect(find.text('No linked tickets.'), findsOneWidget);
  });

  testWidgets('adding a link sends the chosen relation and ticket', (
    tester,
  ) async {
    final http = await _open(
      tester,
      links: _links(),
      extra: {
        'GET /api/v1/tickets': (_) => {
          'items': [_ticket('t1', 'T2026-00001'), _ticket('t2', 'T2026-00002')],
          'total': 2,
        },
        'POST /api/v1/tickets/t1/links': (_) =>
            _links(children: [_linked('t2', 'T2026-00002')]),
      },
    );
    await tester.tap(find.byKey(const ValueKey('add-link')));
    await tester.pumpAndSettle();
    // The ticket itself is not offered.
    expect(find.byKey(const ValueKey('pick-t1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('link-relation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add the other ticket to this bundle').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-t2')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('confirm-link')));
    await tester.pumpAndSettle();

    final sent = http.bodies['POST /api/v1/tickets/t1/links'] as Map;
    expect(sent['relation'], 'child');
    expect(sent['target_id'], 't2');
    expect(find.text('Bundle · 1 of 1 still open'), findsOneWidget);
  });

  testWidgets(
    'a bundle update is previewed, then applied to the chosen tickets',
    (tester) async {
      final requests = <Map>[];
      final http = await _open(
        tester,
        links: _links(
          children: [
            _linked('c1', 'T2026-00002'),
            _linked('c2', 'T2026-00003'),
            _linked('c3', 'T2026-00004'),
          ],
        ),
        extra: {
          'POST /api/v1/tickets/t1/bundle/update': (body) {
            final b = body as Map;
            requests.add(b);
            final dry = b['dry_run'] == true;
            return {
              'dry_run': dry,
              'updated': 2,
              'items': [
                _item(
                  'c1',
                  'T2026-00002',
                  dry ? 'would_apply' : 'applied',
                  recipient: 'a@x.example',
                ),
                _item(
                  'c2',
                  'T2026-00003',
                  dry ? 'would_apply' : 'applied',
                  recipient: 'b@x.example',
                ),
                _item(
                  'c3',
                  'T2026-00004',
                  'failed',
                  reason: 'no recipient: enter an e-mail address',
                ),
              ],
            };
          },
        },
      );
      await tester.tap(find.byKey(const ValueKey('bundle-update')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('bundle-preview')))
            .onPressed,
        isNull,
        reason: 'a message is required',
      );
      await tester.enterText(
        find.byKey(const ValueKey('bundle-body')),
        'We are on it.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('bundle-preview')));
      await tester.pumpAndSettle();

      // The preview shows each ticket, where the mail would go and what is refused.
      expect(requests.single['dry_run'], true);
      expect(requests.single['action'], 'reply');
      expect(find.textContaining('to a@x.example'), findsOneWidget);
      expect(find.textContaining('no recipient'), findsOneWidget);
      expect(find.text('Apply to 2 tickets'), findsOneWidget);

      // Leave one ticket out, then apply.
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('result-c2')),
          matching: find.byType(Checkbox),
        ),
      );
      await tester.pump();
      expect(find.text('Apply to 1 ticket'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bundle-apply')));
      await tester.pumpAndSettle();

      final applied = requests.last;
      expect(applied['dry_run'], false);
      expect(applied['child_ids'], ['c1']);
      expect(applied['body'], 'We are on it.');
      expect(find.text('2 tickets updated.'), findsOneWidget);
      expect(http.requests.where((r) => r.contains('bundle/update')).length, 2);
    },
  );

  testWidgets(
    'without the reply permission the bundle update starts as a note',
    (tester) async {
      final requests = <Map>[];
      await _open(
        tester,
        perms: const ['helpdesk.read', 'helpdesk.write'],
        links: _links(children: [_linked('c1', 'T2026-00002')]),
        extra: {
          'POST /api/v1/tickets/t1/bundle/update': (body) {
            requests.add(body as Map);
            return {
              'dry_run': true,
              'updated': 1,
              'items': [_item('c1', 'T2026-00002', 'would_apply')],
            };
          },
        },
      );
      await tester.tap(find.byKey(const ValueKey('bundle-update')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('bundle-body')), 'FYI');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('bundle-preview')));
      await tester.pumpAndSettle();
      expect(requests.single['action'], 'note');
    },
  );

  for (final locale in ['nl', 'fr', 'de', 'es']) {
    testWidgets('fits the narrow side panel in $locale', (tester) async {
      await _open(
        tester,
        locale: locale,
        width: 348,
        links: _links(
          parent: _linked('p1', 'T2026-00010'),
          related: [_linked('r1', 'T2026-00009')],
        ),
      );
      // An overflow is reported as an exception by the framework.
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('add-link')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
