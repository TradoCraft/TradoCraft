import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/features/packages/intake_page.dart';
import 'package:tradocraft_app/features/packages/link_dialogs.dart';
import 'package:tradocraft_app/features/packages/receiving_page.dart';
import 'package:tradocraft_app/features/repairs/repair_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/photos.dart';

import 'fake_http.dart';

Map<String, Object?> pkgJson(
  String id, {
  String status = 'registered',
  String? kind,
  String? customerId = 'c1',
  String? customerName = 'Alpha Installaties NV',
  String tracking = '3SABC123',
}) => {
  'id': id,
  'number': 'PK-$id',
  'status': status,
  'kind': ?kind,
  'customer_id': ?customerId,
  'customer_name': ?customerName,
  'sender_name': 'Jan Peeters',
  'carrier': 'PostNL',
  'tracking_number': tracking,
  'parcel_count': 1,
  'condition': 'intact',
  'condition_note': '',
  'customer_reference': 'RMA-77',
  'notes': '',
  'photo_count': 0,
  'repair_count': 0,
  'received_at': '2026-11-06T10:00:00Z',
  'received_by': 'u1',
  'received_by_name': 'Dock',
  'created_at': '2026-11-06T10:00:00Z',
  'updated_at': '2026-11-06T10:00:00Z',
};

Map<String, Object?> detail(Map<String, Object?> p) => {
  'package': p,
  'events': <Object?>[],
  'photos': <Object?>[],
  'repairs': <Object?>[],
};

Map<String, Object?> page(List<Object?> items) => {
  'items': items,
  'total': items.length,
};

Map<String, Object?> repair({
  String status = 'announced',
  String customerId = 'c1',
}) => {...repairJson(status: status), 'customer_id': customerId};

Map<String, Object?> suggestion({String customerId = 'c1'}) => {
  'repair': repair(customerId: customerId),
  'score': 8,
  'reasons': ['serial', 'customer'],
};

Future<void> pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
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

const _receiver = ['packages.read', 'packages.write'];
const _intake = [
  'packages.read',
  'packages.write',
  'packages.open',
  'repairs.read',
  'repairs.intake',
  'repairs.route',
];

void main() {
  group('receiving', () {
    testWidgets(
      'registers a parcel with a client id and photo, then clears the form',
      (tester) async {
        final http = FakeHttp({
          'GET /api/v1/me': (_) => meJson(_receiver),
          'GET /api/v1/packages': (_) => page([pkgJson('a1')]),
          'POST /api/v1/packages': (_) => detail(pkgJson('a2')),
          // The form differs from the fixture parcel, so it is brought up to date.
          'PUT /api/v1/packages/a2': (_) => detail(pkgJson('a2')),
          'POST /api/v1/packages/a2/photos': (_) => detail(pkgJson('a2')),
        });
        await pump(
          tester,
          http,
          ReceivingPage(pick: (_) async => [PickedPhoto(fakeJpeg, 'box.jpg')]),
        );
        expect(
          find.text('PK-a1 · Jan Peeters · Alpha Installaties NV'),
          findsOneWidget,
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Tracking number'),
          '3SXYZ',
        );
        await tester.enterText(find.widgetWithText(TextField, 'Sender'), 'Els');
        await tester.tap(find.widgetWithText(ActionChip, 'DHL'));
        await tester.tap(find.byKey(const ValueKey('condition-damaged')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Note on the condition'),
          'Corner crushed',
        );
        await tester.tap(find.text('Add photo'));
        await tester.pumpAndSettle();
        expect(find.text('box.jpg'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Register parcel'));
        await tester.pumpAndSettle();

        final body =
            http.bodies['POST /api/v1/packages']! as Map<String, Object?>;
        expect(body['tracking_number'], '3SXYZ');
        expect(body['sender_name'], 'Els');
        expect(body['carrier'], 'DHL');
        expect(body['condition'], 'damaged');
        expect(body['condition_note'], 'Corner crushed');
        expect(body['parcel_count'], 1);
        expect(body['client_id'], isA<String>());
        expect(http.bodies['POST /api/v1/packages/a2/photos'], fakeJpeg);
        expect(find.text('Parcel PK-a2 registered'), findsOneWidget);
        expect(
          find.text('box.jpg'),
          findsNothing,
          reason: 'form is empty again',
        );
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Tracking number'),
              )
              .controller!
              .text,
          '',
        );
      },
    );

    testWidgets('a retry brings the existing parcel up to date with the form', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_receiver),
        'GET /api/v1/packages': (_) => page([]),
        // The server returns the parcel as first registered.
        'POST /api/v1/packages': (_) => detail(pkgJson('a2', tracking: 'OLD')),
        'PUT /api/v1/packages/a2': (_) =>
            detail(pkgJson('a2', tracking: 'NEW')),
      });
      await pump(tester, http, const ReceivingPage());
      await tester.enterText(
        find.widgetWithText(TextField, 'Tracking number'),
        'NEW',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Register parcel'));
      await tester.pumpAndSettle();
      final put =
          http.bodies['PUT /api/v1/packages/a2']! as Map<String, Object?>;
      expect(put['tracking_number'], 'NEW');
      expect(
        put['client_id'],
        (http.bodies['POST /api/v1/packages']! as Map)['client_id'],
      );
      expect(find.text('Parcel PK-a2 registered'), findsOneWidget);
    });

    testWidgets(
      'a receiver without intake rights can refuse a registered parcel',
      (tester) async {
        final http = FakeHttp({
          'GET /api/v1/me': (_) => meJson(_receiver),
          'GET /api/v1/packages': (_) => page([pkgJson('a1')]),
          'POST /api/v1/packages/a1/close': (_) =>
              detail(pkgJson('a1', status: 'closed')),
        });
        await pump(tester, http, const ReceivingPage());
        await tester.tap(find.text('Close parcel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(
          http.requests,
          isNot(contains('POST /api/v1/packages/a1/close')),
        );
        await tester.tap(find.text('Close parcel'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'Not ours');
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(http.bodies['POST /api/v1/packages/a1/close'], {
          'note': 'Not ours',
        });
        expect(
          http.requests.where((r) => r == 'GET /api/v1/packages').length,
          greaterThan(1),
          reason: 'the list is refreshed',
        );
      },
    );

    testWidgets('people without write rights only see the list', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['packages.read']),
        'GET /api/v1/packages': (_) => page([pkgJson('a1')]),
      });
      await pump(tester, http, const ReceivingPage());
      expect(find.text('Register parcel'), findsNothing);
      expect(find.textContaining('PK-a1'), findsOneWidget);
    });
  });

  group('triage', () {
    FakeHttp intakeHttp({
      Object? Function(Object?)? link,
      List<Object?> suggestions = const [],
      List<String> perms = _intake,
    }) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/packages': (_) {
        return page([]);
      },
      'GET /api/v1/repairs': (_) => page([]),
      'GET /api/v1/departments': (_) => <Object?>[],
    });

    testWidgets('opening as something else needs a note', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_intake),
        'GET /api/v1/packages': (_) => page([pkgJson('a1')]),
        'GET /api/v1/repairs': (_) => page([]),
        'POST /api/v1/packages/a1/open': (_) =>
            detail(pkgJson('a1', status: 'closed', kind: 'other')),
      });
      await pump(tester, http, const IntakePage());
      await tester.tap(find.text('Open parcel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('kind-other')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Open parcel').last,
            )
            .onPressed,
        isNull,
        reason: 'a note is required to close it at once',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Notes'),
        'Just a catalogue',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Open parcel').last);
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/packages/a1/open'], {
        'kind': 'other',
        'note': 'Just a catalogue',
      });
    });

    testWidgets('closing a parcel needs a note', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_intake),
        'GET /api/v1/packages': (_) => page([pkgJson('a1')]),
        'GET /api/v1/repairs': (_) => page([]),
        'POST /api/v1/packages/a1/close': (_) =>
            detail(pkgJson('a1', status: 'closed')),
      });
      await pump(tester, http, const IntakePage());
      await tester.tap(find.text('Close parcel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(http.requests, isNot(contains('POST /api/v1/packages/a1/close')));
      expect(find.text('A note is required.'), findsOneWidget);

      await tester.tap(find.text('Close parcel'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Refused at the dock',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/packages/a1/close'], {
        'note': 'Refused at the dock',
      });
    });

    Future<FakeHttp> openLinkDialog(
      WidgetTester tester, {
      Object? Function(Object?)? link,
      String parcelCustomer = 'c1',
      String repairCustomer = 'c1',
    }) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_intake),
        'GET /api/v1/packages': (_) => page([
          pkgJson(
            'a1',
            status: 'opened',
            kind: 'repair',
            customerId: parcelCustomer,
          ),
        ]),
        'GET /api/v1/repairs': (_) => page([]),
        'GET /api/v1/packages/a1/repair-suggestions': (_) => {
          'proposed_customer_id': 'c1',
          'proposed_customer_name': 'Alpha Installaties NV',
          'suggestions': [suggestion(customerId: repairCustomer)],
        },
        'POST /api/v1/packages/a1/repairs':
            link ??
            (_) => {
              'repair': repair(status: 'received'),
              'events': <Object?>[],
              'photos': <Object?>[],
            },
      });
      await pump(tester, http, const IntakePage());
      await tester.tap(find.text('To process'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match with a repair'));
      await tester.pumpAndSettle();
      return http;
    }

    testWidgets('suggestions show reasons; linking needs an explicit confirm', (
      tester,
    ) async {
      final http = await openLinkDialog(tester);
      expect(find.text('R2026-00001 · Alpha Installaties NV'), findsOneWidget);
      expect(find.text('Same serial number'), findsOneWidget);
      expect(find.text('Same customer'), findsOneWidget);
      expect(find.text('Score 8'), findsOneWidget);

      // Choosing a suggestion only opens the confirm step.
      await tester.tap(find.byKey(const ValueKey('link-r1')));
      await tester.pumpAndSettle();
      expect(find.text('Confirm match'), findsOneWidget);
      expect(
        http.requests,
        isNot(contains('POST /api/v1/packages/a1/repairs')),
      );
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(
        http.requests,
        isNot(contains('POST /api/v1/packages/a1/repairs')),
      );

      await tester.tap(find.byKey(const ValueKey('link-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and link'));
      await tester.pumpAndSettle();
      final body =
          http.bodies['POST /api/v1/packages/a1/repairs']!
              as Map<String, Object?>;
      expect(body['repair_id'], 'r1');
      expect(body['expected_status'], 'announced');
      expect(body['client_id'], isA<String>());
      expect(body.containsKey('confirm_customer_mismatch'), isFalse);
    });

    testWidgets('searching by serial passes it to the suggestions', (
      tester,
    ) async {
      final http = await openLinkDialog(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Serial number'),
        'SN-9',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(http.queries.last['serial'], 'SN-9');
    });

    testWidgets('a conflict is reported and the suggestions are reloaded', (
      tester,
    ) async {
      final http = await openLinkDialog(
        tester,
        link: (_) => const FakeStatus(409, {
          'error': 'conflict',
          'code': 'repair_status_changed',
          'message': 'the repair is received now, not announced',
        }),
      );
      final before = http.requests
          .where((r) => r == 'GET /api/v1/packages/a1/repair-suggestions')
          .length;
      await tester.tap(find.byKey(const ValueKey('link-r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and link'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('The repair has changed in the meantime'),
        findsOneWidget,
      );
      expect(
        http.requests
            .where((r) => r == 'GET /api/v1/packages/a1/repair-suggestions')
            .length,
        before + 1,
      );
      // Still in the dialog, nothing was linked.
      expect(find.text('Suggested repairs'), findsOneWidget);
    });

    testWidgets('a customer mismatch must be acknowledged and is then sent', (
      tester,
    ) async {
      final http = await openLinkDialog(
        tester,
        parcelCustomer: 'c9',
        repairCustomer: 'c1',
      );
      await tester.tap(find.byKey(const ValueKey('link-r1')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The customer of the parcel is not the customer of the repair.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm and link'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm and link'));
      await tester.pumpAndSettle();
      final body =
          http.bodies['POST /api/v1/packages/a1/repairs']!
              as Map<String, Object?>;
      expect(body['confirm_customer_mismatch'], true);
      expect(body['expected_status'], 'announced');
    });

    testWidgets(
      'the server asking for mismatch confirmation re-opens the confirm',
      (tester) async {
        var calls = 0;
        final http = await openLinkDialog(
          tester,
          link: (b) {
            calls++;
            if (calls == 1) {
              return const FakeStatus(409, {
                'error': 'conflict',
                'code': 'customer_mismatch',
                'message': 'worded differently, the code decides',
              });
            }
            return {
              'repair': repair(status: 'received'),
              'events': <Object?>[],
              'photos': <Object?>[],
            };
          },
        );
        await tester.tap(find.byKey(const ValueKey('link-r1')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm and link'));
        await tester.pumpAndSettle();
        expect(find.text('Confirm match'), findsOneWidget);
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Confirm and link'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(
          (http.bodies['POST /api/v1/packages/a1/repairs']!
              as Map<String, Object?>)['confirm_customer_mismatch'],
          true,
        );
      },
    );

    testWidgets('a new repair can be created from the parcel', (tester) async {
      final http = await openLinkDialog(tester);
      await tester.tap(find.text('Create new repair'));
      await tester.pumpAndSettle();
      Finder inDialog(String label) => find.descendant(
        of: find.byType(NewRepairFromParcelDialog),
        matching: find.widgetWithText(TextField, label),
      );
      await tester.enterText(inDialog('Product'), 'Pump 5 kW');
      await tester.enterText(inDialog('Serial number'), 'SN-5');
      await tester.tap(find.widgetWithText(FilledButton, 'Create new repair'));
      await tester.pumpAndSettle();
      final body =
          http.bodies['POST /api/v1/packages/a1/repairs']!
              as Map<String, Object?>;
      final nr = body['new_repair']! as Map<String, Object?>;
      expect(nr['customer_id'], 'c1');
      expect(nr['product_description'], 'Pump 5 kW');
      expect(nr['serial_number'], 'SN-5');
      expect(body.containsKey('repair_id'), isFalse);
    });

    testWidgets('a repair for another customer is asked about first', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_intake),
        'GET /api/v1/packages': (_) =>
            page([pkgJson('a1', status: 'opened', kind: 'repair')]),
        'GET /api/v1/repairs': (_) => page([]),
        'GET /api/v1/customers': (_) => {
          'items': [customerJson()],
          'total': 1,
        },
        'GET /api/v1/packages/a1/repair-suggestions': (_) => {
          'suggestions': <Object?>[],
        },
        'POST /api/v1/packages/a1/repairs': (_) => {
          'repair': repair(status: 'received'),
          'events': <Object?>[],
          'photos': <Object?>[],
        },
      });
      await pump(tester, http, const IntakePage());
      await tester.tap(find.text('To process'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match with a repair'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new repair'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(NewRepairFromParcelDialog),
          matching: find.widgetWithText(TextField, 'Customer'),
        ),
        'Bêta',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Bêta Industrie').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Create new repair'));
      await tester.pumpAndSettle();
      expect(
        http.requests,
        isNot(contains('POST /api/v1/packages/a1/repairs')),
      );
      expect(
        find.textContaining('not the customer of the repair'),
        findsOneWidget,
      );
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create new repair').last,
      );
      await tester.pumpAndSettle();
      final body =
          http.bodies['POST /api/v1/packages/a1/repairs']!
              as Map<String, Object?>;
      expect((body['new_repair']! as Map)['customer_id'], 'c2');
      expect(body['confirm_customer_mismatch'], true);
    });

    testWidgets('received repairs can be routed from the queue', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(_intake),
        'GET /api/v1/packages': (_) => page([]),
        'GET /api/v1/repairs': (_) => page([repair(status: 'received')]),
        'GET /api/v1/departments': (_) => [departmentJson('d1', 'Electronics')],
        'POST /api/v1/repairs/r1/route': (_) => {
          'repair': repairJson(status: 'routed', department: 'Electronics'),
          'events': <Object?>[],
          'photos': <Object?>[],
        },
      });
      await pump(tester, http, const IntakePage());
      await tester.tap(find.text('To route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Route to department'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Electronics').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Route to department').last,
      );
      await tester.pumpAndSettle();
      expect(
        (http.bodies['POST /api/v1/repairs/r1/route']!
            as Map<String, Object?>)['department_id'],
        'd1',
      );
    });

    testWidgets('texts are translated', (tester) async {
      final http = intakeHttp();
      await pump(tester, http, const IntakePage(), locale: 'nl');
      expect(find.text('Reparatie-intake'), findsOneWidget);
      expect(find.text('Te openen'), findsOneWidget);
    });
  });

  group('repair screen', () {
    Map<String, Object?> repairDetail(String status) => {
      'repair': repairJson(status: status),
      'events': <Object?>[],
      'photos': <Object?>[],
    };

    testWidgets('lists linked parcels and unlinks one', (tester) async {
      var unlinked = false;
      final http = FakeHttp({
        'GET /api/v1/me': (_) =>
            meJson(['repairs.read', 'packages.read', 'repairs.intake']),
        'GET /api/v1/repairs/r1': (_) => repairDetail('received'),
        'GET /api/v1/repairs/r1/packages': (_) => unlinked
            ? <Object?>[]
            : [pkgJson('a1', status: 'linked', kind: 'repair')],
        'GET /api/v1/repairs/r1/package-suggestions': (_) => <Object?>[],
        'DELETE /api/v1/packages/a1/repairs/r1': (_) {
          unlinked = true;
          return detail(pkgJson('a1', status: 'opened', kind: 'repair'));
        },
        'GET /api/v1/departments': (_) => <Object?>[],
      });
      await pump(tester, http, const RepairScreen(id: 'r1'));
      expect(find.text('Parcels'), findsOneWidget);
      expect(find.textContaining('PK-a1'), findsOneWidget);
      expect(
        http.requests,
        contains('GET /api/v1/repairs/r1/package-suggestions'),
        reason:
            'a received repair may still have a parcel with its accessories',
      );
      await tester.tap(find.byTooltip('Unlink parcel'));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/packages/a1/repairs/r1'));
      expect(find.textContaining('PK-a1'), findsNothing);
      expect(find.byTooltip('Unlink parcel'), findsNothing);
    });

    testWidgets(
      'an announced repair offers waiting parcels, linked after confirm',
      (tester) async {
        final http = FakeHttp({
          'GET /api/v1/me': (_) =>
              meJson(['repairs.read', 'packages.read', 'repairs.intake']),
          'GET /api/v1/repairs/r1': (_) => repairDetail('announced'),
          'GET /api/v1/repairs/r1/packages': (_) => <Object?>[],
          'GET /api/v1/repairs/r1/package-suggestions': (_) => [
            pkgJson('a7', status: 'opened', kind: 'repair'),
          ],
          'POST /api/v1/packages/a7/repairs': (_) => repairDetail('received'),
          'GET /api/v1/departments': (_) => <Object?>[],
        });
        await pump(tester, http, const RepairScreen(id: 'r1'));
        expect(find.text('Parcels waiting for this repair'), findsOneWidget);
        await tester.tap(find.text('Link parcel'));
        await tester.pumpAndSettle();
        expect(
          http.requests,
          isNot(contains('POST /api/v1/packages/a7/repairs')),
        );
        await tester.tap(find.text('Confirm and link'));
        await tester.pumpAndSettle();
        final body =
            http.bodies['POST /api/v1/packages/a7/repairs']!
                as Map<String, Object?>;
        expect(body['repair_id'], 'r1');
        expect(body['expected_status'], 'announced');
      },
    );

    testWidgets('without package rights the section is not shown', (
      tester,
    ) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['repairs.read']),
        'GET /api/v1/repairs/r1': (_) => repairDetail('received'),
        'GET /api/v1/departments': (_) => <Object?>[],
      });
      await pump(tester, http, const RepairScreen(id: 'r1'));
      expect(find.text('Parcels'), findsNothing);
    });
  });

  group('navigation', () {
    Future<void> pumpShell(WidgetTester tester, List<String> perms) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final http = FakeHttp({'GET /api/v1/me': (_) => meJson(perms)});
      final router = GoRouter(
        initialLocation: '/packages',
        routes: [
          ShellRoute(
            builder: (context, state, child) =>
                AppShell(location: state.matchedLocation, child: child),
            routes: [
              for (final p in ['/packages', '/intake', '/repairs'])
                GoRoute(path: p, builder: (_, _) => Text('page $p')),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dioProvider.overrideWithValue(fakeDio(http))],
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('en'),
            localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('goods in sees receiving only', (tester) async {
      await pumpShell(tester, ['packages.read', 'packages.write']);
      expect(find.text('Receiving'), findsOneWidget);
      expect(find.text('Repair intake'), findsNothing);
    });

    testWidgets('repair intake sees both sections', (tester) async {
      await pumpShell(tester, [
        'packages.read',
        'repairs.intake',
        'repairs.read',
      ]);
      expect(find.text('Receiving'), findsOneWidget);
      expect(find.text('Repair intake'), findsOneWidget);
    });

    testWidgets('nobody without the rights sees them', (tester) async {
      await pumpShell(tester, ['repairs.read']);
      expect(find.text('Receiving'), findsNothing);
      expect(find.text('Repair intake'), findsNothing);
    });
  });
}
