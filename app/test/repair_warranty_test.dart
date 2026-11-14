import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/repairs/repair_screen.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> unitJson(String id, String serial) => {
  'id': id,
  'product_id': 'p1',
  'product_code': 'PUMP-05',
  'product_name': 'Pump 0.5 kW',
  'serial_number': serial,
  'warranty_until': '2027-03-01',
};

Map<String, Object?> warrantyJson({
  String warranty = 'in_warranty',
  String auto = 'in_warranty',
  bool overridden = false,
  bool unit = true,
  List<Object?> candidates = const [],
}) => {
  'repair_id': 'r1',
  'warranty': warranty,
  'auto': auto,
  'auto_until': '2027-03-01',
  'auto_at': '2026-11-06T10:00:00Z',
  'compared_with': '2026-11-06',
  'arrived': true,
  'serial_unit': unit ? unitJson('u1', 'SN-1') : null,
  'candidates': candidates,
  'overridden': overridden,
  'override_by': overridden ? 'u9' : null,
  'override_by_name': overridden ? 'Els Electronics' : null,
  'override_at': overridden ? '2026-11-07T09:00:00Z' : null,
  'override_reason': overridden ? 'Water damage' : '',
};

Map<String, Object?> detailJson({
  String warranty = 'in_warranty',
  bool overridden = false,
  String findings = '',
}) => {
  'repair': {
    ...repairJson(status: 'in_progress', department: 'Electronics'),
    'warranty': warranty,
    'warranty_auto': 'in_warranty',
    'warranty_overridden': overridden,
    'findings': findings,
  },
  'events': <Object?>[],
  'photos': <Object?>[],
};

Future<void> pump(
  WidgetTester tester,
  FakeHttp http, {
  String locale = 'en',
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RepairScreen(id: 'r1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, Object? Function(Object?)> baseRoutes(
  List<String> perms, {
  Map<String, Object?> warranty = const {},
  Map<String, Object?>? detail,
}) => {
  'GET /api/v1/me': (_) => meJson(perms),
  'GET /api/v1/repairs/r1': (_) => detail ?? detailJson(),
  'GET /api/v1/repairs/r1/warranty': (_) => {...warrantyJson(), ...warranty},
  'GET /api/v1/departments': (_) => <Object?>[],
  'GET /api/v1/repairs/r1/packages': (_) => <Object?>[],
};

void main() {
  testWidgets('the card shows the automatic result next to the final status', (
    tester,
  ) async {
    final http = FakeHttp(baseRoutes(['repairs.read']));
    await pump(tester, http);
    expect(find.text('Warranty'), findsWidgets);
    expect(
      find.text('Automatic result: In warranty (until 01/03/2027)'),
      findsOneWidget,
    );
    expect(
      find.text('Compared with the arrival date 06/11/2026'),
      findsOneWidget,
    );
    expect(find.text('Serial unit: PUMP-05 · SN-1'), findsOneWidget);
    // Read-only: no actions for someone without the rights.
    expect(find.text('Mark warranty void (misuse)'), findsNothing);
    expect(find.byTooltip('Check warranty again'), findsNothing);
    expect(find.byTooltip('Unlink serial unit'), findsNothing);
  });

  testWidgets('the void dialog needs a reason and sends it', (tester) async {
    var overridden = false;
    final http = FakeHttp({
      ...baseRoutes(['repairs.read', 'repairs.write', 'repairs.warranty_void']),
      'GET /api/v1/repairs/r1/warranty': (_) => warrantyJson(
        warranty: overridden ? 'void' : 'in_warranty',
        overridden: overridden,
      ),
      'PUT /api/v1/repairs/r1/warranty/override': (_) {
        overridden = true;
        return detailJson(warranty: 'void', overridden: true);
      },
    });
    await pump(tester, http);
    await tester.tap(find.text('Mark warranty void (misuse)'));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(
      FilledButton,
      'Mark warranty void (misuse)',
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason (required)'),
      '   ',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason (required)'),
      'Water damage',
    );
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/repairs/r1/warranty/override']!
          as Map<String, Object?>)['reason'],
      'Water damage',
    );
    // The automatic result stays visible next to the override.
    expect(
      find.text('Automatic result: In warranty (until 01/03/2027)'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Overridden to void by Els Electronics on 07/11/2026: Water damage',
      ),
      findsOneWidget,
    );
    expect(find.text('Void (misuse)'), findsWidgets);
    expect(find.text('Remove override'), findsOneWidget);
    expect(find.text('Mark warranty void (misuse)'), findsNothing);
  });

  testWidgets('removing the override asks for a reason too', (tester) async {
    final http = FakeHttp({
      ...baseRoutes([
        'repairs.read',
        'repairs.write',
        'repairs.warranty_void',
      ], detail: detailJson(warranty: 'void', overridden: true)),
      'GET /api/v1/repairs/r1/warranty': (_) =>
          warrantyJson(warranty: 'void', overridden: true),
      'DELETE /api/v1/repairs/r1/warranty/override': (_) => detailJson(),
    });
    await pump(tester, http);
    await tester.tap(find.text('Remove override'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason (required)'),
      'Factory fault',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove override'));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['DELETE /api/v1/repairs/r1/warranty/override']!
          as Map<String, Object?>)['reason'],
      'Factory fault',
    );
  });

  testWidgets('without the void right the override is shown but not offered', (
    tester,
  ) async {
    final http = FakeHttp({
      ...baseRoutes(['repairs.read', 'repairs.write']),
      'GET /api/v1/repairs/r1/warranty': (_) =>
          warrantyJson(warranty: 'void', overridden: true),
    });
    await pump(tester, http);
    expect(find.byKey(const ValueKey('warranty-override')), findsOneWidget);
    expect(find.text('Remove override'), findsNothing);
    expect(find.text('Mark warranty void (misuse)'), findsNothing);
  });

  testWidgets('intake picks one of several matching serial units', (
    tester,
  ) async {
    final http = FakeHttp({
      ...baseRoutes(['repairs.read', 'repairs.write', 'repairs.intake']),
      'GET /api/v1/repairs/r1/warranty': (_) => warrantyJson(
        warranty: 'unknown',
        auto: 'unknown',
        unit: false,
        candidates: [unitJson('u1', 'SN-1'), unitJson('u2', 'SN-1')],
      ),
      'PUT /api/v1/repairs/r1/serial-unit': (_) => detailJson(),
    });
    await pump(tester, http);
    expect(find.text('No serial unit linked'), findsOneWidget);
    expect(
      find.text('Several serial units match. Pick the right one.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Link serial unit'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unit-u2')));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/repairs/r1/serial-unit']!
          as Map<String, Object?>)['serial_unit_id'],
      'u2',
    );
  });

  testWidgets('a linked unit can be unlinked and the lookup rerun', (
    tester,
  ) async {
    final http = FakeHttp({
      ...baseRoutes(['repairs.read', 'repairs.write', 'repairs.intake']),
      'PUT /api/v1/repairs/r1/serial-unit': (_) => detailJson(),
      'POST /api/v1/repairs/r1/warranty/recheck': (_) => warrantyJson(),
    });
    await pump(tester, http);
    await tester.tap(find.byTooltip('Unlink serial unit'));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['PUT /api/v1/repairs/r1/serial-unit']!
          as Map<String, Object?>)['clear'],
      true,
    );
    await tester.tap(find.byTooltip('Check warranty again'));
    await tester.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/repairs/r1/warranty/recheck'));
  });

  testWidgets('findings are edited by people who work on the repair', (
    tester,
  ) async {
    final http = FakeHttp({
      ...baseRoutes(['repairs.read', 'repairs.write']),
      'PUT /api/v1/repairs/r1/findings': (_) =>
          detailJson(findings: 'Burnt smell'),
    });
    await pump(tester, http);
    await tester.enterText(
      find.widgetWithText(TextField, 'What was found'),
      'Burnt smell',
    );
    await tester.tap(find.text('Save findings'));
    await tester.pumpAndSettle();
    final body =
        http.bodies['PUT /api/v1/repairs/r1/findings']! as Map<String, Object?>;
    expect(body['findings'], 'Burnt smell');
  });

  testWidgets('without write rights the findings are only shown', (
    tester,
  ) async {
    final http = FakeHttp(
      baseRoutes(['repairs.read'], detail: detailJson(findings: 'Burnt smell')),
    );
    await pump(tester, http);
    expect(find.text('Burnt smell'), findsOneWidget);
    expect(find.text('Save findings'), findsNothing);
    expect(find.widgetWithText(TextField, 'What was found'), findsNothing);
  });

  testWidgets('the card speaks Dutch', (tester) async {
    final http = FakeHttp({
      ...baseRoutes(['repairs.read']),
      'GET /api/v1/repairs/r1/warranty': (_) =>
          warrantyJson(warranty: 'void', overridden: true),
    });
    await pump(tester, http, locale: 'nl');
    expect(find.text('Garantie'), findsWidgets);
    expect(find.text('Vervallen (misbruik)'), findsWidgets);
  });
}
