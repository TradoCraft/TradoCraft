import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/helpdesk/helpdesk_mailboxes.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _mailbox({
  String id = 'mb1',
  String name = 'Support',
  String kind = 'graph',
  bool isDefault = false,
  bool active = true,
  bool inbound = true,
  String? lastOkAt,
  String? lastError,
}) => {
  'id': id,
  'name': name,
  'address': '${name.toLowerCase()}@contoso.example',
  'kind': kind,
  'team_id': kind == 'graph' ? 'team1' : null,
  'team_name': kind == 'graph' ? 'Support NL' : null,
  'is_default': isDefault,
  'active': active,
  'inbound_enabled': inbound,
  'secret_ref': name.toUpperCase(),
  'tenant_id': kind == 'graph' ? 'contoso.onmicrosoft.com' : null,
  'client_id': kind == 'graph' ? 'app-1' : null,
  'username': kind == 'graph' ? null : 'helpdesk',
  'imap_host': kind == 'graph' ? null : 'mail.example.com',
  'imap_port': null,
  'imap_tls': true,
  'imap_folder': 'INBOX',
  'smtp_host': kind == 'graph' ? null : 'mail.example.com',
  'smtp_port': 465,
  'smtp_security': 'tls',
  'last_poll_at':
      lastOkAt ?? (lastError == null ? null : '2027-01-27T08:00:00Z'),
  'last_ok_at': lastOkAt,
  'last_error': lastError,
  'created_at': '2027-01-27T07:00:00Z',
};

Map<String, Object?> _team() => {
  'id': 'team1',
  'name': 'Support NL',
  'active': true,
  'members': <Object?>[],
  'created_at': '2026-11-01T09:00:00Z',
};

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, {
  String locale = 'en',
}) async {
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
        home: const Scaffold(
          body: SingleChildScrollView(child: MailboxesCard()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the list shows each mailbox with its state in words', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/helpdesk/teams': (_) => [_team()],
      'GET /api/v1/helpdesk/mailboxes': (_) => [
        _mailbox(isDefault: true, lastOkAt: '2027-01-27T08:00:00Z'),
        _mailbox(
          id: 'mb2',
          name: 'Parts',
          kind: 'imap_smtp',
          lastError: 'the worker has no MAILBOX_SECRET_PARTS variable',
        ),
        _mailbox(id: 'mb3', name: 'Old', active: false, lastError: 'x'),
        _mailbox(id: 'mb4', name: 'Noreply', inbound: false),
        _mailbox(id: 'mb5', name: 'Fresh'),
      ],
    });
    await _pump(tester, http);

    expect(find.text('Support (default)'), findsOneWidget);
    expect(
      find.text(
        'support@contoso.example · Microsoft 365 (Exchange Online) · Support NL',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('E-mail last fetched on 27/01/2027'), findsOne);
    expect(find.text('parts@contoso.example · IMAP and SMTP'), findsOneWidget);
    expect(
      find.text(
        'Fetching e-mail failed: the worker has no MAILBOX_SECRET_PARTS variable',
      ),
      findsOneWidget,
    );
    // A mailbox that is switched off shows that, not its old error.
    final old = tester.widget<Text>(
      find.byKey(const ValueKey('mailbox-status-mb3')),
    );
    expect(old.data, 'inactive');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('mailbox-status-mb4')))
          .data,
      'Sends only',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('mailbox-status-mb5')))
          .data,
      'No e-mail fetched yet',
    );
  });

  testWidgets('an empty list says how mail is handled without mailboxes', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/helpdesk/teams': (_) => <Object?>[],
      'GET /api/v1/helpdesk/mailboxes': (_) => <Object?>[],
    });
    await _pump(tester, http, locale: 'nl');
    expect(find.text('Mailboxen'), findsOneWidget);
    expect(find.textContaining('Nog geen mailboxen.'), findsOneWidget);
  });

  testWidgets('a Microsoft 365 mailbox is created with only its own fields', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/helpdesk/teams': (_) => [_team()],
      'GET /api/v1/helpdesk/mailboxes': (_) => <Object?>[],
      'POST /api/v1/helpdesk/mailboxes': (_) => _mailbox(),
    });
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('new-mailbox')));
    await tester.pumpAndSettle();

    // Graph is the first choice: no IMAP or SMTP fields, and no field for a password.
    expect(find.byKey(const ValueKey('mailbox-tenant')), findsOneWidget);
    expect(find.byKey(const ValueKey('mailbox-imap-host')), findsNothing);
    expect(find.textContaining('MAILBOX_SECRET_SUPPORT'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('mailbox-name')),
      'Support',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mailbox-address')),
      'support@contoso.example',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mailbox-tenant')),
      'contoso.onmicrosoft.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mailbox-client')),
      'app-1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('mailbox-secret-ref')),
      'helpdesk_nl',
    );
    await tester.pump();
    // The help text names the variable to set on the server.
    expect(find.textContaining('MAILBOX_SECRET_HELPDESK_NL'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('mailbox-default')));
    await tester.tap(find.byKey(const ValueKey('mailbox-default')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-mailbox')));
    await tester.pumpAndSettle();

    expect(http.bodies['POST /api/v1/helpdesk/mailboxes'], {
      'name': 'Support',
      'address': 'support@contoso.example',
      'kind': 'graph',
      'secret_ref': 'HELPDESK_NL',
      'is_default': true,
      'active': true,
      'inbound_enabled': true,
      'imap_tls': true,
      'tenant_id': 'contoso.onmicrosoft.com',
      'client_id': 'app-1',
    });
    // Saved: the dialog is closed and the list is read again.
    expect(find.byKey(const ValueKey('save-mailbox')), findsNothing);
    expect(
      http.requests.where((r) => r == 'GET /api/v1/helpdesk/mailboxes').length,
      2,
    );
  });

  testWidgets(
    'an IMAP/SMTP mailbox is edited, a refusal is shown, then removed',
    (tester) async {
      var refuse = true;
      final http = FakeHttp({
        'GET /api/v1/helpdesk/teams': (_) => [_team()],
        'GET /api/v1/helpdesk/mailboxes': (_) => [
          _mailbox(id: 'mb2', name: 'Parts', kind: 'imap_smtp'),
        ],
        'PUT /api/v1/helpdesk/mailboxes/mb2': (_) => refuse
            ? const FakeStatus(422, {
                'error': 'validation',
                'message': 'fetching mail needs the IMAP server',
              })
            : _mailbox(id: 'mb2', name: 'Parts', kind: 'imap_smtp'),
        'DELETE /api/v1/helpdesk/mailboxes/mb2': (_) =>
            const FakeStatus(204, null),
      });
      await _pump(tester, http);
      await tester.tap(find.byKey(const ValueKey('mailbox-mb2')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mailbox-tenant')), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey('mailbox-imap-host')),
        '',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('save-mailbox')));
      await tester.tap(find.byKey(const ValueKey('save-mailbox')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mailbox-error')), findsOneWidget);
      expect(find.textContaining('needs the IMAP server'), findsOneWidget);

      refuse = false;
      await tester.enterText(
        find.byKey(const ValueKey('mailbox-imap-host')),
        'imap.example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('mailbox-imap-port')),
        '993',
      );
      await tester.tap(find.byKey(const ValueKey('save-mailbox')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/helpdesk/mailboxes/mb2'], {
        'name': 'Parts',
        'address': 'parts@contoso.example',
        'kind': 'imap_smtp',
        'secret_ref': 'PARTS',
        'is_default': false,
        'active': true,
        'inbound_enabled': true,
        'username': 'helpdesk',
        'imap_host': 'imap.example.com',
        'imap_port': 993,
        'imap_tls': true,
        'imap_folder': 'INBOX',
        'smtp_host': 'mail.example.com',
        'smtp_port': 465,
        'smtp_security': 'tls',
      });

      // Removing asks first.
      await tester.tap(find.byKey(const ValueKey('mailbox-mb2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-mailbox')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Remove the mailbox Parts?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-mailbox')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/helpdesk/mailboxes/mb2'));
    },
  );
}
