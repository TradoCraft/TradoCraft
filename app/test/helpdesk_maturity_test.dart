import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/helpdesk_settings_page.dart';
import 'package:tradocraft_app/features/helpdesk/ticket_screen.dart';
import 'package:tradocraft_app/features/helpdesk/tickets_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/portal/portal_csat.dart';
import 'package:tradocraft_app/portal/portal_pages.dart';
import 'package:tradocraft_app/portal/portal_state.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

const _helpdeskPerms = [
  'helpdesk.read',
  'helpdesk.write',
  'helpdesk.reply',
  'quotations.write',
];

Map<String, Object?> _sla(String state, {int? left, bool paused = false}) => {
  'state': state,
  'paused': paused,
  'first_response': {
    'due_at': '2026-11-09T12:00:00Z',
    'breached': state == 'breached',
    'at_risk': state == 'at_risk',
    'minutes_remaining': left,
  },
  'resolution': {
    'due_at': '2026-11-12T10:00:00Z',
    'breached': false,
    'at_risk': false,
    'minutes_remaining': 4000,
  },
  'first_response_breached': state == 'breached',
  'resolution_breached': false,
};

Map<String, Object?> _ticket({
  String id = 't1',
  String number = 'T2026-00007',
  String subject = 'Pump is noisy',
  Map<String, Object?>? sla,
  List<String> tags = const [],
  String? teamId,
  String? csat,
}) => {
  'id': id,
  'number': number,
  'subject': subject,
  'status': 'open',
  'priority': 'normal',
  'category': 'service',
  'language': 'en',
  'customer_id': 'c1',
  'customer_name': 'Alpha NV',
  'contact_name': 'Anna',
  'contact_email': 'anna@alpha.example',
  'internal': false,
  'article_count': 1,
  'created_at': '2026-11-09T09:00:00Z',
  'updated_at': '2026-11-09T09:00:00Z',
  ...ticketExtras(),
  'sla': sla ?? ticketExtras()['sla'],
  'tags': tags,
  'team_id': teamId,
  'team_name': teamId == null ? null : 'Support NL',
  'csat_rating': csat,
  'csat_comment': csat == null ? null : 'Too slow',
  'csat_rated_at': csat == null ? null : '2026-11-10T09:00:00Z',
};

Map<String, Object?> _article({List<Map<String, Object?>> files = const []}) =>
    {
      'id': 'a1',
      'kind': 'email_in',
      'from_address': 'anna@alpha.example',
      'from_name': 'Anna',
      'to_addresses': ['sales@example.com'],
      'cc_addresses': <String>[],
      'subject': 'Pump',
      'body': 'It is loud.',
      'attachments': files,
      'created_at': '2026-11-09T09:00:00Z',
    };

Map<String, Object?> _file(String id, String name, String type) => {
  'id': id,
  'filename': name,
  'content_type': type,
  'size_bytes': 2048,
  'uploader_name': 'Anna',
  'created_at': '2026-11-09T09:00:00Z',
};

Map<String, Object?> _team() => {
  'id': 'team1',
  'name': 'Support NL',
  'active': true,
  'members': [
    {'user_id': 'u1', 'display_name': 'Support Agent', 'is_lead': true},
  ],
  'created_at': '2026-11-01T09:00:00Z',
};

Map<String, Object?> _user() => {
  'id': 'u1',
  'display_name': 'Support Agent',
  'email': 'support@example.com',
  'roles': ['support'],
};

Future<void> _pumpStaff(WidgetTester tester, FakeHttp http, Widget home) async {
  tester.view.physicalSize = const Size(1700, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPortal(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portalDioProvider.overrideWithValue(fakeDio(http)),
        initialPortalTokenProvider.overrideWithValue('tcs_x'),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<List<PickedPhoto>> _pickPdf(BuildContext _) async => [
  PickedPhoto(Uint8List.fromList('%PDF-1.4\n'.codeUnits), 'plan.pdf'),
];

void main() {
  testWidgets('the ticket list shows the SLA state and filters on it', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(_helpdeskPerms),
      'GET /api/v1/helpdesk/teams': (_) => [_team()],
      'GET /api/v1/helpdesk/tags': (_) => [
        {'tag': 'warranty', 'count': 2},
      ],
      'GET /api/v1/tickets': (_) => {
        'items': [
          _ticket(sla: _sla('breached', left: -30), teamId: 'team1'),
          _ticket(
            id: 't2',
            number: 'T2026-00008',
            sla: _sla('at_risk', left: 10),
          ),
        ],
        'total': 2,
      },
    });
    await _pumpStaff(tester, http, const Scaffold(body: TicketsPage()));

    expect(find.text('Breached · 30m overdue'), findsOneWidget);
    expect(find.text('At risk · 10m left'), findsOneWidget);
    expect(find.text('Support NL'), findsWidgets, reason: 'team column');
    // "My tickets" is the default: mine, not an owner id.
    expect(http.queries.last['mine'], true);

    await tester.tap(find.byKey(const ValueKey('filter-sla')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('At risk').last);
    await tester.pumpAndSettle();
    expect(http.queries.last['sla'], 'at_risk');

    await tester.tap(find.byKey(const ValueKey('filter-team')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Support NL').last);
    await tester.pumpAndSettle();
    expect(http.queries.last['team_id'], 'team1');

    await tester.tap(find.byKey(const ValueKey('filter-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('warranty (2)').last);
    await tester.pumpAndSettle();
    expect(http.queries.last['tag'], 'warranty');
    expect(http.queries.last['team_id'], 'team1', reason: 'filters combine');

    await tester.tap(find.text('Unassigned'));
    await tester.pumpAndSettle();
    expect(http.queries.last['unassigned'], true);
    expect(http.queries.last['mine'], isNull);
  });

  testWidgets(
    'the ticket shows SLA, tags, time, rating and attachments, and merges',
    (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_helpdeskPerms),
        'GET /api/v1/users': (_) => [_user()],
        'GET /api/v1/helpdesk/teams': (_) => [_team()],
        'GET /api/v1/tickets/t1': (_) => {
          'ticket': _ticket(
            sla: _sla('at_risk', left: 10),
            tags: ['warranty'],
            csat: 'bad',
          ),
          ...detailExtras(),
          'articles': [
            _article(files: [_file('f1', 'drawing.pdf', 'application/pdf')]),
          ],
        },
        'GET /api/v1/quotations': (_) => {'items': [], 'total': 0},
        'GET /api/v1/opportunities': (_) => {'items': [], 'total': 0},
        'GET /api/v1/customers/c1/contacts': (_) => [],
        'GET /api/v1/tickets/t1/repairs': (_) => [],
        'GET /api/v1/tickets/t1/time-entries': (_) => {
          'items': [
            {
              'id': 'e1',
              'user_id': 'u1',
              'user_name': 'Support Agent',
              'minutes': 75,
              'note': 'phone call',
              'billable': true,
              'created_at': '2026-11-09T10:00:00Z',
            },
          ],
          'total_minutes': 75,
          'billable_minutes': 75,
        },
        'POST /api/v1/tickets/t1/time-entries': (_) => {
          'items': <Object?>[],
          'total_minutes': 90,
          'billable_minutes': 75,
        },
        'POST /api/v1/tickets/t1/tags': (_) => {
          'ticket': _ticket(tags: ['urgent', 'warranty']),
          ...detailExtras(),
          'articles': <Object?>[],
        },
        'POST /api/v1/tickets/t1/attachments': (_) =>
            _file('f2', 'plan.pdf', 'application/pdf'),
        'POST /api/v1/tickets/t1/replies': (_) => {
          'ticket': _ticket(),
          ...detailExtras(),
          'articles': <Object?>[],
        },
        'PUT /api/v1/tickets/t1/assignment': (_) => {
          'ticket': _ticket(teamId: 'team1'),
          ...detailExtras(),
          'articles': <Object?>[],
        },
        'GET /api/v1/tickets': (_) => {
          'items': [
            _ticket(),
            _ticket(id: 't9', number: 'T2026-00009', subject: 'Other'),
          ],
          'total': 2,
        },
        'POST /api/v1/tickets/t1/merge': (_) => {
          'ticket': _ticket(id: 't9', number: 'T2026-00009'),
          ...detailExtras(),
          'articles': <Object?>[],
        },
      });
      await _pumpStaff(
        tester,
        http,
        TicketScreen(id: 't1', pickFiles: _pickPdf),
      );

      // SLA in the header and in the details.
      expect(find.text('At risk · 10m left'), findsOneWidget);
      expect(find.byKey(const ValueKey('sla-section')), findsOneWidget);
      expect(find.text('10m left · Due 09/11/2026'), findsOneWidget);
      // Tag, time with total, and the customer's rating with comment.
      expect(find.byKey(const ValueKey('tag-warranty')), findsOneWidget);
      expect(find.text('1 h 15 min · Billable · phone call'), findsOneWidget);
      expect(find.byKey(const ValueKey('time-total')), findsOneWidget);
      expect(find.text('Not satisfied'), findsOneWidget);
      expect(find.text('"Too slow"'), findsOneWidget);
      // The attachment of the customer's mail.
      expect(find.byKey(const ValueKey('attachment-f1')), findsOneWidget);
      expect(find.text('drawing.pdf · 2 KB'), findsOneWidget);

      // Add a tag.
      await tester.ensureVisible(find.byKey(const ValueKey('new-tag')));
      await tester.enterText(find.byKey(const ValueKey('new-tag')), 'urgent');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/tickets/t1/tags'], {'tag': 'urgent'});

      // Log time.
      await tester.ensureVisible(find.byKey(const ValueKey('log-time')));
      await tester.tap(find.byKey(const ValueKey('log-time')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('time-minutes')), '15');
      await tester.tap(find.text('Billable').last);
      await tester.pump();
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/tickets/t1/time-entries'], {
        'minutes': 15,
        'note': '',
        'billable': true,
      });

      // Choose a team.
      await tester.ensureVisible(find.text('No team'));
      await tester.tap(find.text('No team'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support NL').last);
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/tickets/t1/assignment'], {
        'team_id': 'team1',
      });

      // Attach a file to the reply: it is uploaded first, then sent along by id.
      await tester.tap(find.byKey(const ValueKey('attach-file')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/tickets/t1/attachments'));
      expect(
        http.queries[http.requests.indexOf(
          'POST /api/v1/tickets/t1/attachments',
        )]['filename'],
        'plan.pdf',
      );
      expect(find.byKey(const ValueKey('pending-f2')), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Message'),
        'See plan',
      );
      // Let the snack bars go: they float over the send button.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      final sent = http.bodies['POST /api/v1/tickets/t1/replies'] as Map;
      expect(sent['attachment_ids'], ['f2']);
      expect(find.byKey(const ValueKey('pending-f2')), findsNothing);

      // Merge into the other ticket of the customer.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('merge-ticket')));
      await tester.tap(find.byKey(const ValueKey('merge-ticket')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('merge-t1')),
        findsNothing,
        reason: 'not itself',
      );
      expect(find.byKey(const ValueKey('confirm-merge')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('confirm-merge')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const ValueKey('merge-t9')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('confirm-merge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(http.bodies['POST /api/v1/tickets/t1/merge'], {'target_id': 't9'});
      expect(find.text('Tickets merged'), findsOneWidget);
    },
  );

  testWidgets('admins edit SLA policies, teams and the survey setting', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson([..._helpdeskPerms, 'helpdesk.admin']),
      'GET /api/v1/users': (_) => [_user()],
      'GET /api/v1/helpdesk/teams': (_) => [_team()],
      'GET /api/v1/helpdesk/mailboxes': (_) => <Object?>[],
      'GET /api/v1/helpdesk/settings': (_) => {
        'default_team_id': null,
        'csat_enabled': false,
      },
      'GET /api/v1/helpdesk/sla-policies': (_) => [
        for (final (p, f, r) in [
          ('urgent', 60, 480),
          ('high', 240, 1440),
          ('normal', 480, 4320),
          ('low', 1440, 7200),
        ])
          {'priority': p, 'first_response_minutes': f, 'resolution_minutes': r},
      ],
      'PUT /api/v1/helpdesk/sla-policies': (_) => <Object?>[],
      'PUT /api/v1/helpdesk/settings': (_) => {
        'default_team_id': 'team1',
        'csat_enabled': true,
      },
      'POST /api/v1/helpdesk/teams': (_) => _team(),
    });
    await _pumpStaff(tester, http, const HelpdeskSettingsPage());

    // Service levels.
    expect(find.text('Support NL'), findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('first-normal')), '30');
    await tester.tap(find.byKey(const ValueKey('save-policies')));
    await tester.pumpAndSettle();
    final put = http.bodies['PUT /api/v1/helpdesk/sla-policies'] as Map;
    final policies = (put['policies'] as List).cast<Map>();
    expect(policies, hasLength(4));
    expect(policies.firstWhere((p) => p['priority'] == 'normal'), {
      'priority': 'normal',
      'first_response_minutes': 30,
      'resolution_minutes': 4320,
    });

    // A new team with one lead.
    await tester.tap(find.byKey(const ValueKey('new-team')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('team-name')),
      'Sales desk',
    );
    await tester.tap(find.byKey(const ValueKey('member-u1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('lead-u1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-team')));
    await tester.pumpAndSettle();
    expect(http.bodies['POST /api/v1/helpdesk/teams'], {
      'name': 'Sales desk',
      'active': true,
      'members': [
        {'user_id': 'u1', 'is_lead': true},
      ],
    });

    // Default team and survey.
    await tester.ensureVisible(find.byKey(const ValueKey('csat-enabled')));
    await tester.tap(find.byKey(const ValueKey('csat-enabled')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-settings')));
    await tester.pumpAndSettle();
    expect(http.bodies['PUT /api/v1/helpdesk/settings'], {
      'csat_enabled': true,
    });
  });

  testWidgets('without the admin permission the settings stay closed', (
    tester,
  ) async {
    final http = FakeHttp({'GET /api/v1/me': (_) => meJson(_helpdeskPerms)});
    await _pumpStaff(tester, http, const HelpdeskSettingsPage());
    expect(find.byKey(const ValueKey('sla-policies')), findsNothing);
    expect(
      find.text('You do not have permission to change these settings.'),
      findsOneWidget,
    );
  });

  testWidgets('customers see files on messages and attach files to a reply', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/portal/tickets/t1': (_) => {
        'ticket': {
          'id': 't1',
          'number': 'T2026-00001',
          'subject': 'Pomp lekt',
          'status': 'open',
          'category': 'service',
          'contact_name': 'Sofie',
          'created_at': '2026-11-05T10:00:00Z',
          'updated_at': '2026-11-05T11:00:00Z',
        },
        'messages': [
          {
            'id': 'm1',
            'direction': 'outgoing',
            'author_name': 'Support Agent',
            'body': 'Here is the quote.',
            'attachments': [_file('f1', 'quote.pdf', 'application/pdf')],
            'created_at': '2026-11-05T11:00:00Z',
          },
        ],
      },
      'POST /api/v1/portal/tickets/t1/attachments': (_) =>
          _file('f9', 'plan.pdf', 'application/pdf'),
      'POST /api/v1/portal/tickets/t1/messages': (_) => {
        'ticket': {
          'id': 't1',
          'number': 'T2026-00001',
          'subject': 'Pomp lekt',
          'status': 'open',
          'category': 'service',
          'contact_name': 'Sofie',
          'created_at': '2026-11-05T10:00:00Z',
          'updated_at': '2026-11-05T11:00:00Z',
        },
        'messages': <Object?>[],
      },
      'GET /api/v1/portal/tickets': (_) => <Object?>[],
    });
    await _pumpPortal(
      tester,
      http,
      Scaffold(
        body: PortalTicketPage(id: 't1', pickFiles: _pickPdf),
      ),
    );
    expect(find.text('quote.pdf · 2 KB'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('attach-file')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-f9')), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'The plan');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(http.bodies['POST /api/v1/portal/tickets/t1/messages'], {
      'body': 'The plan',
      'attachment_ids': ['f9'],
    });
  });

  group('satisfaction survey page', () {
    Map<String, Object?> info(String state) => {
      'ticket_number': 'T2026-00001',
      'subject': 'Pomp lekt',
      'company_name': 'Demo',
      'language': 'nl',
      'state': state,
      'rating': state == 'rated' ? 'good' : null,
    };

    testWidgets('the link preselects the rating; it is sent once confirmed', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/csat/tcq_abc': (_) => info('open'),
        'POST /api/v1/csat/tcq_abc': (_) => info('rated'),
      });
      await _pumpPortal(
        tester,
        http,
        PortalCsatPage(
          key: const ValueKey('tcq_abc'),
          link: const CsatLink('tcq_abc', 'bad'),
        ),
      );
      // Reading the page records nothing, and it speaks the language of the ticket.
      expect(http.requests, ['GET /api/v1/csat/tcq_abc']);
      expect(
        find.text(
          'Hoe tevreden bent u over de afhandeling van ticket T2026-00001?',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'Te traag');
      await tester.tap(find.byKey(const ValueKey('send-rating')));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/csat/tcq_abc'], {
        'rating': 'bad',
        'comment': 'Te traag',
      });
      expect(find.text('Bedankt voor uw feedback!'), findsOneWidget);
    });

    testWidgets('answered, expired and unknown links say so', (tester) async {
      final answered = FakeHttp({
        'GET /api/v1/csat/tcq_a': (_) => info('rated'),
      });
      await _pumpPortal(
        tester,
        answered,
        PortalCsatPage(
          key: const ValueKey('tcq_a'),
          link: const CsatLink('tcq_a', 'good'),
        ),
      );
      expect(find.text('Deze enquête werd al beantwoord.'), findsOneWidget);

      final expired = FakeHttp({
        'GET /api/v1/csat/tcq_e': (_) => info('expired'),
      });
      await _pumpPortal(
        tester,
        expired,
        PortalCsatPage(
          key: const ValueKey('tcq_e'),
          link: const CsatLink('tcq_e', null),
        ),
      );
      expect(find.text('Deze link is verlopen.'), findsOneWidget);

      await _pumpPortal(
        tester,
        FakeHttp({}),
        PortalCsatPage(
          key: const ValueKey('tcq_nope'),
          link: const CsatLink('tcq_nope', null),
        ),
        locale: 'en',
      );
      expect(find.text('This survey link has expired.'), findsOneWidget);
    });

    test('the survey link is read from the address fragment', () {
      final l = csatLinkFromUri(
        Uri.parse('https://p.example/csat#token=tcq_abc&rating=good'),
      );
      expect((l?.token, l?.rating), ('tcq_abc', 'good'));
      expect(csatLinkFromUri(Uri.parse('https://p.example/csat')), isNull);
      expect(
        csatLinkFromUri(Uri.parse('https://p.example/csat#token=tcl_login')),
        isNull,
      );
    });
  });
}
