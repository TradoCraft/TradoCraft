import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _provider(
  String? id,
  String name, {
  String issuer = 'https://login.example.com',
  String policy = 'require_verified_claim',
  List<String> domains = const [],
  bool enabled = true,
  bool env = false,
}) => {
  'id': id,
  'source': env ? 'env' : 'database',
  'read_only': env,
  'name': name,
  'issuer': issuer,
  'audience': 'aud-$name',
  'client_id': null,
  'scopes': 'openid profile email',
  'algorithms': ['RS256'],
  'email_claim': 'email',
  'email_policy': policy,
  'verified_claim': 'email_verified',
  'allowed_email_domains': domains,
  'enabled': enabled,
};

Map<String, Object?> _user(String id, String name) => {
  'user_id': id,
  'email': '$id@example.com',
  'display_name': name,
  'roles': ['sales'],
  'disabled_modules': <String>[],
  'active': true,
  'has_signed_in': true,
};

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, {
  bool openIdentity = true,
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
              return const AdminPage();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (openIdentity) {
    await tester.tap(find.text('Identity providers').first);
    await tester.pumpAndSettle();
  }
}

Map<String, Object? Function(Object?)> _routes({
  List<String> perms = const ['users.admin', 'identity.admin'],
  bool primary = true,
  Object? Function(Object?)? list,
  Map<String, Object? Function(Object?)>? extra,
}) => {
  'GET /api/v1/me': (_) => meJson(perms, primary: primary),
  'GET /api/v1/admin/users': (_) => [_user('u2', 'Sam Sales')],
  'GET /api/v1/admin/modules': (_) => [],
  'GET /api/v1/roles': (_) => [],
  'GET /api/v1/admin/identity-providers':
      list ??
      (_) => [
        _provider('p1', 'Entra', domains: ['example.com']),
        _provider(
          null,
          'Environment (OIDC_ISSUER)',
          issuer: 'https://env.example',
          env: true,
        ),
      ],
  ...?extra,
};

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(ValueKey(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

/// Fills the minimum valid form.
Future<void> _fillBasics(WidgetTester tester) async {
  await _enter(tester, 'idp-name', 'Keycloak');
  await _enter(tester, 'idp-issuer', 'https://sso.example.com/realms/acme');
  await _enter(tester, 'idp-audience', 'tradocraft');
}

void main() {
  testWidgets('lists providers; the environment one is read-only', (
    tester,
  ) async {
    await _pump(tester, FakeHttp(_routes()));
    expect(find.text('Primary company: Demo'), findsOneWidget);
    expect(
      find.text(
        "Only administrators of the installation's primary company can change these settings.",
      ),
      findsOneWidget,
    );
    expect(find.text('Entra'), findsOneWidget);
    expect(find.text('Links people by e-mail when the claim email_verified is true, only for example.com'), findsOneWidget);
    expect(find.text('Saved in the app'), findsOneWidget);
    expect(find.text('Environment (OIDC_ISSUER)'), findsOneWidget);
    expect(find.text('Server environment'), findsOneWidget);
    expect(find.textContaining('OIDC_ISSUER / OIDC_AUDIENCE'), findsOneWidget);
    expect(find.byKey(const ValueKey('idp-edit-p1')), findsOneWidget);
    expect(find.byKey(const ValueKey('idp-edit-null')), findsNothing);
    expect(find.byKey(const ValueKey('idp-del-null')), findsNothing);
  });

  testWidgets('the segment needs identity.admin', (tester) async {
    await _pump(
      tester,
      FakeHttp(_routes(perms: ['users.admin'])),
      openIdentity: false,
    );
    expect(find.text('Identity providers'), findsNothing);
    expect(find.text('Modules'), findsOneWidget);
  });

  testWidgets('shows an explanation instead of failing when not primary', (
    tester,
  ) async {
    final http = FakeHttp(
      _routes(
        primary: false,
        list: (_) => const FakeStatus(403, {
          'error': 'forbidden',
          'message': 'identity providers are managed by an administrator of the installation\'s primary company',
        }),
      ),
    );
    await _pump(tester, http);
    expect(find.byKey(const ValueKey('idp-readonly')), findsOneWidget);
    expect(find.textContaining('not an administrator'), findsOneWidget);
    expect(find.textContaining('Server error'), findsNothing);
    final add = tester.widget<FilledButton>(find.byKey(const ValueKey('idp-add')));
    expect(add.onPressed, isNull);
  });

  testWidgets('presets fill the fields', (tester) async {
    await _pump(tester, FakeHttp(_routes()));
    await _tap(tester, 'idp-add');
    await _tap(tester, 'idp-preset-entra');
    expect(_text(tester, 'idp-name'), 'Microsoft Entra ID');
    await _enter(tester, 'idp-tenant', 'tenant-1');
    expect(
      _text(tester, 'idp-issuer'),
      'https://login.microsoftonline.com/tenant-1/v2.0',
    );
    expect(find.textContaining('xms_edov'), findsWidgets);
    final trust = tester.widget<RadioListTile<String>>(
      find.byKey(const ValueKey('idp-rule-trust_provider_email')),
    );
    expect(trust.value, 'trust_provider_email');
    expect(find.byKey(const ValueKey('idp-domain-input')), findsOneWidget);

    await _tap(tester, 'idp-preset-google');
    expect(_text(tester, 'idp-issuer'), 'https://accounts.google.com');
    expect(_text(tester, 'idp-verified-claim'), 'email_verified');
    expect(find.byKey(const ValueKey('idp-tenant')), findsNothing);

    await _tap(tester, 'idp-preset-generic');
    expect(find.byKey(const ValueKey('idp-tenant')), findsNothing);
  });

  testWidgets('validates before sending anything', (tester) async {
    final http = FakeHttp(_routes());
    await _pump(tester, http);
    await _tap(tester, 'idp-add');
    await _tap(tester, 'idp-save');
    expect(find.text('A name is required.'), findsOneWidget);
    expect(find.text('The issuer must be an https:// URL.'), findsOneWidget);
    expect(find.text('The audience is required.'), findsOneWidget);

    await _fillBasics(tester);
    await _enter(tester, 'idp-issuer', 'http://sso.example.com');
    await _tap(tester, 'idp-save');
    expect(find.text('The issuer must be an https:// URL.'), findsOneWidget);
    await _enter(tester, 'idp-issuer', 'https://sso.example.com');
    await _enter(tester, 'idp-domain-input', 'not a domain');
    await _tap(tester, 'idp-save');
    expect(find.text('not a domain does not look like a domain.'), findsOneWidget);
    expect(http.requests, isNot(contains('POST /api/v1/admin/identity-providers')));
  });

  testWidgets('creates a provider with the typed settings', (tester) async {
    final http = FakeHttp(
      _routes(
        extra: {
          'POST /api/v1/admin/identity-providers': (_) =>
              _provider('p2', 'Keycloak'),
        },
      ),
    );
    await _pump(tester, http);
    await _tap(tester, 'idp-add');
    await _fillBasics(tester);
    await _enter(tester, 'idp-client-id', 'app-1');
    await _tap(tester, 'idp-rule-trust_provider_email');
    await _enter(tester, 'idp-domain-input', '@Example.com');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('idp-domain-example.com')), findsOneWidget);
    await _tap(tester, 'idp-save');
    final body = http.bodies['POST /api/v1/admin/identity-providers']! as Map;
    expect(body['name'], 'Keycloak');
    expect(body['issuer'], 'https://sso.example.com/realms/acme');
    expect(body['audience'], 'tradocraft');
    expect(body['client_id'], 'app-1');
    expect(body['email_policy'], 'trust_provider_email');
    expect(body['allowed_email_domains'], ['example.com']);
    expect(body['enabled'], true);
    expect((body['algorithms'] as List).length, 8);
    expect(body.containsKey('confirm_lockout'), false);
    expect(find.byKey(const ValueKey('idp-save')), findsNothing);
  });

  testWidgets('updates a provider and shows the server reason of a 422', (
    tester,
  ) async {
    var calls = 0;
    final http = FakeHttp(
      _routes(
        extra: {
          'PUT /api/v1/admin/identity-providers/p1': (_) {
            calls++;
            return calls == 1
                ? const FakeStatus(422, {
                    'error': 'validation',
                    'message': 'cannot read the identity provider: timeout',
                  })
                : _provider('p1', 'Renamed');
          },
        },
      ),
    );
    await _pump(tester, http);
    await _tap(tester, 'idp-edit-p1');
    expect(_text(tester, 'idp-name'), 'Entra');
    await _enter(tester, 'idp-name', 'Renamed');
    await _tap(tester, 'idp-save');
    expect(
      find.text(
        'The server refused these settings: cannot read the identity provider: timeout',
      ),
      findsOneWidget,
    );
    await _tap(tester, 'idp-save');
    final body = http.bodies['PUT /api/v1/admin/identity-providers/p1']! as Map;
    expect(body['name'], 'Renamed');
    expect(body['allowed_email_domains'], ['example.com']);
    expect(find.byKey(const ValueKey('idp-save')), findsNothing);
  });

  testWidgets('test button shows a readable report for a sample token', (
    tester,
  ) async {
    final http = FakeHttp(
      _routes(
        extra: {
          'POST /api/v1/admin/identity-providers/test': (_) => {
            'discovery_reachable': true,
            'issuer_match': true,
            'discovery_issuer': 'https://sso.example.com',
            'key_count': 2,
            'key_algorithms': ['RS256', 'ES256'],
            'claims_supported': ['sub', 'email'],
            'token': {
              'signature_ok': true,
              'audience_ok': true,
              'expiry_ok': true,
              'valid': true,
              'email': 'ann@example.com',
              'email_verified': true,
              'binding': {
                'outcome': 'would_bind',
                'user_email': 'ann@example.com',
                'user_id': 'u9',
              },
            },
          },
        },
      ),
    );
    await _pump(tester, http);
    await _tap(tester, 'idp-add');
    await _fillBasics(tester);
    await _enter(tester, 'idp-sample-token', 'aaa.bbb.ccc');
    await _tap(tester, 'idp-test');
    final body =
        http.bodies['POST /api/v1/admin/identity-providers/test']! as Map;
    expect(body['sample_token'], 'aaa.bbb.ccc');
    expect((body['config'] as Map)['issuer'], 'https://sso.example.com/realms/acme');
    expect(find.text('Discovery document reachable'), findsOneWidget);
    expect(find.text('2 signing keys, algorithms: RS256, ES256'), findsOneWidget);
    expect(find.text('Claims the provider says it supports: sub, email'), findsOneWidget);
    expect(find.text('Signature: OK'), findsOneWidget);
    expect(find.text('E-mail found: ann@example.com'), findsOneWidget);
    expect(find.text('The provider marks the address as verified'), findsOneWidget);
    expect(find.text('Would sign in as ann@example.com'), findsOneWidget);
    expect(find.textContaining('Nothing is linked or stored'), findsOneWidget);
    expect(http.requests, isNot(contains('POST /api/v1/admin/identity-providers')));
  });

  testWidgets('a refused sample token is explained', (tester) async {
    final http = FakeHttp(
      _routes(
        extra: {
          'POST /api/v1/admin/identity-providers/test': (_) => {
            'discovery_reachable': true,
            'issuer_match': true,
            'key_count': 1,
            'key_algorithms': ['RS256'],
            'token': {
              'signature_ok': true,
              'expiry_ok': false,
              'valid': false,
              'reason': 'the token has expired',
            },
          },
        },
      ),
    );
    await _pump(tester, http);
    await _tap(tester, 'idp-add');
    await _fillBasics(tester);
    await _tap(tester, 'idp-test');
    expect(find.text('Not expired: Failed'), findsOneWidget);
    expect(find.text('the token has expired'), findsOneWidget);
  });

  group('lock-out safeguards', () {
    for (final code in ['last_identity_provider', 'own_identity_provider']) {
      testWidgets('$code: confirm retries with confirm_lockout', (tester) async {
        final bodies = <Map>[];
        final http = FakeHttp(
          _routes(
            extra: {
              'PUT /api/v1/admin/identity-providers/p1': (b) {
                bodies.add(b! as Map);
                if ((b as Map)['confirm_lockout'] == true) {
                  return _provider('p1', 'Entra', enabled: false);
                }
                return FakeStatus(409, {
                  'error': 'conflict',
                  'code': code,
                  'message': 'x',
                });
              },
            },
          ),
        );
        await _pump(tester, http);
        await _tap(tester, 'idp-edit-p1');
        await _tap(tester, 'idp-enabled');
        await _tap(tester, 'idp-save');
        expect(find.text('This can lock people out'), findsOneWidget);
        expect(
          find.textContaining(
            code == 'last_identity_provider'
                ? 'last enabled identity provider'
                : 'You are signed in through this provider',
          ),
          findsOneWidget,
        );
        await _tap(tester, 'idp-lockout-confirm');
        expect(bodies.length, 2);
        expect(bodies.first.containsKey('confirm_lockout'), false);
        expect(bodies.last['confirm_lockout'], true);
        expect(bodies.last['enabled'], false);
        expect(find.byKey(const ValueKey('idp-save')), findsNothing);
      });
    }

    testWidgets('cancel does not retry', (tester) async {
      final http = FakeHttp(
        _routes(
          extra: {
            'PUT /api/v1/admin/identity-providers/p1': (_) => const FakeStatus(
              409,
              {
                'error': 'conflict',
                'code': 'own_identity_provider',
                'message': 'x',
              },
            ),
          },
        ),
      );
      await _pump(tester, http);
      await _tap(tester, 'idp-edit-p1');
      await _tap(tester, 'idp-save');
      await _tap(tester, 'idp-lockout-cancel');
      expect(
        http.requests.where((r) => r.startsWith('PUT ')).length,
        1,
      );
      expect(find.byKey(const ValueKey('idp-save')), findsOneWidget);
    });

    testWidgets('delete asks twice for a lock-out and sends the query', (
      tester,
    ) async {
      final http = FakeHttp(
        _routes(
          extra: {
            'DELETE /api/v1/admin/identity-providers/p1': (_) => null,
          },
        ),
      );
      // The first delete answers 409; replace the route with a stateful one.
      var first = true;
      http.routes['DELETE /api/v1/admin/identity-providers/p1'] = (_) {
        if (first) {
          first = false;
          return const FakeStatus(409, {
            'error': 'conflict',
            'code': 'last_identity_provider',
            'message': 'x',
          });
        }
        return null;
      };
      await _pump(tester, http);
      await _tap(tester, 'idp-del-p1');
      expect(find.textContaining('Delete identity provider Entra?'), findsOneWidget);
      await _tap(tester, 'idp-delete-confirm');
      expect(find.text('This can lock people out'), findsOneWidget);
      expect(http.queries.last, isEmpty);
      await _tap(tester, 'idp-lockout-confirm');
      expect(http.queries[http.requests.lastIndexWhere((r) => r.startsWith('DELETE '))]['confirm_lockout'], true);
      expect(
        http.requests.where((r) => r.startsWith('DELETE ')).length,
        2,
      );
    });
  });

  testWidgets('cancelling the delete confirmation sends nothing', (
    tester,
  ) async {
    final http = FakeHttp(_routes());
    await _pump(tester, http);
    await _tap(tester, 'idp-del-p1');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(http.requests.where((r) => r.startsWith('DELETE ')), isEmpty);
  });

  group('link identity', () {
    testWidgets('sets and clears the subject', (tester) async {
      final http = FakeHttp(
        _routes(
          extra: {'PUT /api/v1/admin/users/u2/oidc-subject': (_) => null},
        ),
      );
      await _pump(tester, http, openIdentity: false);
      await tester.tap(find.text('Users').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('link-identity-u2')));
      await tester.pumpAndSettle();
      expect(find.textContaining("'Only existing subjects'"), findsOneWidget);
      // Only saved providers are offered, not the environment one.
      await _enter(tester, 'link-subject', ' sub-77 ');
      await _tap(tester, 'link-save');
      expect(http.bodies['PUT /api/v1/admin/users/u2/oidc-subject'], {
        'issuer': 'https://login.example.com',
        'subject': 'sub-77',
      });

      await tester.tap(find.byKey(const ValueKey('link-identity-u2')));
      await tester.pumpAndSettle();
      await _tap(tester, 'link-save');
      expect(http.bodies['PUT /api/v1/admin/users/u2/oidc-subject'], {});
    });

    testWidgets('is hidden without identity.admin', (tester) async {
      await _pump(
        tester,
        FakeHttp(_routes(perms: ['users.admin'])),
        openIdentity: false,
      );
      expect(find.text('Sam Sales'), findsOneWidget);
      expect(find.text('Link identity'), findsNothing);
    });
  });
}
