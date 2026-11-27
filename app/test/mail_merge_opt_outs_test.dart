import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/customers/mail_merge_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/portal/portal_state.dart';
import 'package:tradocraft_app/portal/portal_unsubscribe.dart';

import 'fake_http.dart';

const _merge = '/api/v1/customers/mail-merge';

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  required List<Override> overrides,
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object?> _recipient(
  String name,
  String email,
  List<String> issues,
) => {
  'customer_id': 'c-$name',
  'customer_name': name,
  'contact_id': null,
  'contacts': <Object>[],
  'language': 'en',
  'email': email,
  'subject': 'New brochure',
  'body': 'Dear $name',
  'footer': 'Unsubscribe here: https://p/unsubscribe#token=…',
  'pdf': 'memo-en.pdf',
  'issues': issues,
};

void main() {
  group('staff mail merge', () {
    testWidgets(
      'opted-out recipients are labelled and the register is managed',
      (tester) async {
        var register = <Map<String, Object?>>[
          {
            'email': 'gone@example.test',
            'opted_out_at': '2026-11-20T10:00:00Z',
            'source': 'unsubscribe_link',
          },
        ];
        final http = FakeHttp({
          'GET /api/v1/kb/documents': (_) => <Object>[],
          'GET $_merge': (_) => {
            'approval_id': 'a1',
            'draft': null,
            'audience': [
              _recipient('Gone Ltd', 'gone@example.test', ['opted_out']),
              _recipient('Here Ltd', 'here@example.test', []),
            ],
          },
          'GET $_merge/history': (_) => <Object>[],
          'GET $_merge/opt-outs': (_) => register,
          'POST $_merge/opt-outs': (body) {
            register = [
              {
                'email': (body as Map)['email'],
                'opted_out_at': '2026-11-26T10:00:00Z',
                'source': 'staff',
                'recorded_by': 'u1',
                'recorded_by_name': 'Admin User',
              },
              ...register,
            ];
            return null;
          },
          'DELETE $_merge/opt-outs/gone%40example.test': (_) {
            register = [
              for (final r in register)
                if (r['email'] != 'gone@example.test') r,
            ];
            return null;
          },
        });
        await _pump(
          tester,
          const MailMergePage(),
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
        );
        expect(
          find.text('gone@example.test · Unsubscribed from mailings'),
          findsOneWidget,
        );
        expect(find.text('here@example.test'), findsOneWidget);
        expect(
          find.text(
            "Every email ends with an unsubscribe link in the recipient's language.",
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('mail-merge-opt-outs')));
        await tester.pumpAndSettle();
        expect(find.text('Unsubscribed addresses'), findsWidgets);
        expect(find.textContaining('Via the unsubscribe link'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('opt-out-email')),
          'new@example.test',
        );
        await tester.tap(find.byKey(const ValueKey('opt-out-add')));
        await tester.pumpAndSettle();
        expect(http.bodies['POST $_merge/opt-outs'], {
          'email': 'new@example.test',
        });
        expect(find.textContaining('Added by Admin User'), findsOneWidget);

        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('gone@example.test')),
            matching: find.byTooltip('Remove'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          http.requests,
          contains('DELETE $_merge/opt-outs/gone%40example.test'),
        );
        expect(find.textContaining('Via the unsubscribe link'), findsNothing);

        // The register changed: the preview must be saved again before confirming.
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Save to refresh the preview.'), findsOneWidget);
      },
    );

    testWidgets('the barrier does not close; Back still reports the change', (
      tester,
    ) async {
      var register = <Map<String, Object?>>[];
      final http = FakeHttp({
        'GET /api/v1/kb/documents': (_) => <Object>[],
        'GET $_merge': (_) => {
          'approval_id': 'a1',
          'draft': null,
          'audience': [_recipient('Here Ltd', 'here@example.test', [])],
        },
        'GET $_merge/history': (_) => <Object>[],
        'GET $_merge/opt-outs': (_) => register,
        'POST $_merge/opt-outs': (body) {
          register = [
            {
              'email': (body as Map)['email'],
              'opted_out_at': '2026-11-26T10:00:00Z',
              'source': 'staff',
            },
          ];
          return null;
        },
      });
      await _pump(
        tester,
        const MailMergePage(),
        overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      );
      await tester.tap(find.byKey(const ValueKey('mail-merge-opt-outs')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('opt-out-email')),
        'new@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('opt-out-add')));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('opt-out-close')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('opt-out-close')), findsNothing);
      expect(find.text('Save to refresh the preview.'), findsOneWidget);
    });
  });

  group('portal unsubscribe', () {
    Map<String, Object?> info({bool unsubscribed = false}) => {
      'company_name': 'Demo Manufacturing BV',
      'email': 'j***@example.test',
      'language': 'nl',
      'unsubscribed': unsubscribed,
    };

    testWidgets('reading changes nothing; confirming unsubscribes', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/mailing-unsubscribe/tcu_abc': (_) => info(),
        'POST /api/v1/mailing-unsubscribe/tcu_abc': (_) => null,
      });
      await _pump(
        tester,
        const PortalUnsubscribePage(token: 'tcu_abc'),
        overrides: [portalDioProvider.overrideWithValue(fakeDio(http))],
      );
      expect(http.requests, ['GET /api/v1/mailing-unsubscribe/tcu_abc']);
      // In the language of the mailing.
      expect(
        find.text(
          'Wilt u geen mailings van Demo Manufacturing BV meer ontvangen op j***@example.test?',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('unsubscribe')));
      await tester.pumpAndSettle();
      expect(http.requests.last, 'POST /api/v1/mailing-unsubscribe/tcu_abc');
      expect(
        find.text('U bent uitgeschreven. U ontvangt deze mailings niet meer.'),
        findsOneWidget,
      );
    });

    testWidgets('already unsubscribed and invalid links say so', (
      tester,
    ) async {
      await _pump(
        tester,
        const PortalUnsubscribePage(key: ValueKey('a'), token: 'tcu_a'),
        overrides: [
          portalDioProvider.overrideWithValue(
            fakeDio(
              FakeHttp({
                'GET /api/v1/mailing-unsubscribe/tcu_a': (_) =>
                    info(unsubscribed: true),
              }),
            ),
          ),
        ],
      );
      expect(find.text('Dit adres is al uitgeschreven.'), findsOneWidget);
      expect(find.byKey(const ValueKey('unsubscribe')), findsNothing);

      await _pump(
        tester,
        const PortalUnsubscribePage(key: ValueKey('b'), token: 'tcu_nope'),
        overrides: [portalDioProvider.overrideWithValue(fakeDio(FakeHttp({})))],
      );
      expect(find.text('This unsubscribe link is not valid.'), findsOneWidget);

      await _pump(
        tester,
        const PortalUnsubscribePage(key: ValueKey('c'), token: null),
        overrides: [portalDioProvider.overrideWithValue(fakeDio(FakeHttp({})))],
      );
      expect(find.text('This unsubscribe link is not valid.'), findsOneWidget);
    });

    test('the unsubscribe token is read from the address fragment', () {
      expect(
        unsubscribeTokenFromUri(
          Uri.parse('https://p.example/unsubscribe#token=tcu_abc'),
        ),
        'tcu_abc',
      );
      expect(
        unsubscribeTokenFromUri(Uri.parse('https://p.example/unsubscribe')),
        isNull,
      );
      expect(
        unsubscribeTokenFromUri(
          Uri.parse('https://p.example/csat#token=tcq_abc&rating=good'),
        ),
        isNull,
      );
    });
  });
}
