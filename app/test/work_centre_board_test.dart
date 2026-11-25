import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/planning/resource_board.dart';
import 'package:tradocraft_app/features/production/work_centre_board_adapter.dart';
import 'package:tradocraft_app/features/production/work_centre_board_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

// The week of Monday 9 November 2026.
final _monday = DateTime(2026, 11, 9);

String _d(int day) => '2026-11-${day.toString().padLeft(2, '0')}';

Map<String, Object?> _centre(String id, String code, {int overloadedDay = 0}) =>
    {
      'id': id,
      'code': code,
      'name': 'Work centre $code',
      'division_id': null,
      'active': true,
      'capacity': 1,
      'days': [
        for (var day = 9; day <= 15; day++)
          {
            'date': _d(day),
            'available_minutes': day <= 13 ? 480 : 0,
            'load_minutes': day == overloadedDay ? 600 : (day == 9 ? 240 : 0),
            'overloaded': day == overloadedDay,
          },
      ],
      'total_available_minutes': 2400,
      'total_load_minutes': 240,
    };

Map<String, Object?> _op(
  String id,
  String order,
  String name,
  String centre,
  int start,
  int end, {
  bool late = false,
  String status = 'pending',
}) => {
  'id': id,
  'production_order_id': 'p-$order',
  'order_number': order,
  'product_name': 'Frame',
  'position': 1,
  'name': name,
  'status': status,
  'work_centre_id': centre,
  'planned_minutes': 240,
  'planned_start': _d(start),
  'planned_end': _d(end),
  'predecessor_end': null,
  'successor_start': null,
  'planned_ready_date': null,
  'late': late,
  'locked': status != 'pending',
};

Map<String, Object?> _board() => {
  'from': _d(9),
  'to': _d(15),
  'centres': [_centre('c1', 'SAW', overloadedDay: 10), _centre('c2', 'WELD')],
  'operations': [
    _op('o1', 'PO-1', 'Cut', 'c1', 9, 9),
    _op('o2', 'PO-1', 'Weld', 'c2', 10, 11, status: 'in_progress'),
    _op('o3', 'PO-2', 'Drill', 'c1', 2, 4, late: true),
  ],
};

/// A server for the board: moving anything onto WELD on Wednesday is an overload.
FakeHttp _server({
  List<String> permissions = const ['production.read', 'production.write'],
  // The second request for the board (the next week) waits for this.
  Completer<void>? holdReload,
  // Every check and move waits for this.
  Completer<void>? holdMoves,
}) {
  late FakeHttp http;
  var boards = 0;
  Future<Object?> move(Object? body) async {
    final q = Map<String, dynamic>.of(http.queries.last);
    if (holdMoves != null) await holdMoves.future;
    final overload = [
      {
        'kind': 'overload',
        'severity': 'error',
        'message_key': 'production.conflict.overload',
        'day': _d(11),
      },
    ];
    if (q['dry_run'] == true) {
      return {'applied': false, 'conflicts': overload, 'order': null};
    }
    if (q['force'] != true) {
      return const FakeStatus(409, {
        'error': 'conflict',
        'message': 'move conflicts: production.conflict.overload',
      });
    }
    return {'applied': true, 'conflicts': overload, 'order': null};
  }

  http = FakeHttp({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET /api/v1/production/planning-board': (_) async {
      boards++;
      if (boards > 1 && holdReload != null) await holdReload.future;
      return _board();
    },
    'PUT /api/v1/production-orders/p-PO-1/operations/o1/move': move,
  });
  return http;
}

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, {
  Size size = const Size(1700, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => WorkCentreBoardPage(initialDay: _monday),
      ),
      GoRoute(
        path: '/production/:id',
        builder: (_, s) => Text('order page ${s.pathParameters['id']}'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Carries the Cut block over the Wednesday cell of WELD.
Future<TestGesture> _dragCutToWeldWednesday(WidgetTester tester) async {
  final block = tester.getCenter(
    find.byKey(const ValueKey('block-o1-2026-11-09')),
  );
  final cell = tester.getRect(find.byKey(const ValueKey('cell-c2-2026-11-11')));
  final g = await tester.startGesture(block);
  await tester.pump(const Duration(milliseconds: 250));
  await g.moveBy(const Offset(0, 6));
  await tester.pump();
  await g.moveTo(cell.center);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  return g;
}

/// The PUT requests that changed something (not the dry-run checks), as (index, request).
List<(int, String)> _realMoves(FakeHttp http) => [
  for (final (i, r) in http.requests.indexed)
    if (r.startsWith('PUT') && http.queries[i]['dry_run'] != true) (i, r),
];

void main() {
  testWidgets(
    'shows the centres, the operations, the shading and the late list',
    (tester) async {
      final http = _server();
      await _pump(tester, http);
      expect(find.text('SAW'), findsOneWidget);
      expect(find.text('WELD'), findsOneWidget);
      expect(find.textContaining('PO-1 · Cut'), findsWidgets);
      expect(find.textContaining('PO-1 · Weld'), findsWidgets);
      // The week was requested.
      expect(
        http.queries.firstWhere((q) => q.containsKey('from'))['from'],
        startsWith('2026-11-09'),
      );
      expect(
        http.queries.firstWhere((q) => q.containsKey('to'))['to'],
        startsWith('2026-11-15'),
      );
      // Closed days and the overloaded day are shaded.
      expect(
        find.byKey(const ValueKey('shade-closure-c1-2026-11-14')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shade-overload-c1-2026-11-10')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shade-overload-c2-2026-11-10')),
        findsNothing,
      );
      // Utilisation of the week: 240 of 2400 minutes.
      expect(find.byKey(const ValueKey('wc-util-c1')), findsOneWidget);
      expect(find.text('10%'), findsNWidgets(2));
      // The late operation is listed beside the grid, not on it.
      expect(find.text('Late operations'), findsOneWidget);
      expect(find.text('PO-2 · Drill'), findsOneWidget);
      expect(find.byKey(const ValueKey('block-o3-2026-11-09')), findsNothing);
      // Tapping a block opens its production order.
      await tester.tap(find.byKey(const ValueKey('block-o1-2026-11-09')));
      await tester.pumpAndSettle();
      expect(find.text('order page p-PO-1'), findsOneWidget);
    },
  );

  testWidgets('dragging checks the move, and an error needs a confirmation', (
    tester,
  ) async {
    final http = _server();
    await _pump(tester, http);
    final g = await _dragCutToWeldWednesday(tester);
    // The check ran without changing anything and its result is shown while dragging.
    expect(http.queries.last['dry_run'], true);
    expect(find.byKey(const ValueKey('wc-conflict-banner')), findsOneWidget);
    expect(
      find.textContaining('Wed 11 Nov would be overloaded.'),
      findsOneWidget,
    );
    await g.up();
    await tester.pumpAndSettle();
    // Dropping with an error asks first.
    expect(find.text('Move with conflicts?'), findsOneWidget);
    expect(_realMoves(http), isEmpty, reason: 'only dry runs so far');
    await tester.tap(find.text('Move anyway'));
    await tester.pumpAndSettle();
    final real = _realMoves(http);
    expect(real.length, 1);
    final last = http.queries[real.single.$1];
    expect(last['force'], true);
    expect(last.containsKey('dry_run'), false);
    final body =
        http.bodies['PUT /api/v1/production-orders/p-PO-1/operations/o1/move']
            as Map;
    expect(body['work_centre_id'], 'c2');
    expect(body['planned_start'], startsWith('2026-11-11'));
    expect(body['planned_end'], startsWith('2026-11-11'));
    expect(find.text('Operation moved.'), findsOneWidget);
    // The board was loaded again.
    expect(http.requests.where((r) => r.contains('planning-board')).length, 2);
  });

  testWidgets('cancelling the confirmation moves nothing', (tester) async {
    final http = _server();
    await _pump(tester, http);
    final g = await _dragCutToWeldWednesday(tester);
    await g.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_realMoves(http), isEmpty, reason: 'dry runs only');
    expect(find.text('Operation moved.'), findsNothing);
  });

  testWidgets('a running operation and a reader cannot be dragged', (
    tester,
  ) async {
    final http = _server(permissions: const ['production.read']);
    await _pump(tester, http);
    expect(find.byType(BoardDraggable), findsNothing);
    final block = tester.getCenter(
      find.byKey(const ValueKey('block-o1-2026-11-09')),
    );
    final g = await tester.startGesture(block);
    await tester.pump(const Duration(milliseconds: 250));
    await g.moveBy(const Offset(0, 80));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(http.requests.where((r) => r.startsWith('PUT')), isEmpty);
    // A writer still cannot drag the running Weld operation.
    final writer = _server();
    await _pump(tester, writer);
    expect(
      find.byType(BoardDraggable),
      findsOneWidget,
      reason: 'only the pending Cut',
    );
  });

  test('the body of a move keeps the number of calendar days and always names the centre', () {
    final op = ProductionBoardOperation.fromJson(
      _op('o9', 'PO-9', 'Weld', 'c1', 9, 11),
    );
    final other = moveBody(op, 'c2', DateTime(2026, 11, 16, 7));
    expect(other.workCentreId, 'c2');
    expect(other.plannedStart, DateTime(2026, 11, 16));
    expect(other.plannedEnd, DateTime(2026, 11, 18));
    // The same centre is named too, so a stale board cannot leave the operation where somebody
    // else moved it.
    final same = moveBody(op, 'c1', DateTime(2026, 11, 12));
    expect(same.workCentreId, 'c1');
    // An operation within one day stays within one day.
    final oneDay = ProductionBoardOperation.fromJson(
      _op('o8', 'PO-8', 'Cut', 'c1', 9, 9),
    );
    expect(
      moveBody(oneDay, 'c1', DateTime(2026, 11, 12)).plannedEnd,
      DateTime(2026, 11, 12),
    );
    expect(canForce([]), true);
    expect(
      canForce([
        ProductionMoveConflict(
          kind: 'operation_started',
          severity: 'error',
          messageKey: 'production.conflict.operation_started',
        ),
      ]),
      false,
    );
  });

  test('calendar days are not shortened by a daylight-saving change', () {
    // The clocks change on 25 October 2026 in Europe and on 1 November in North America, on 29
    // March and 8 March in spring: a local difference of two such days is 47 or 49 hours.
    expect(calendarDays(DateTime(2026, 10, 24), DateTime(2026, 10, 26)), 2);
    expect(calendarDays(DateTime(2026, 10, 31), DateTime(2026, 11, 2)), 2);
    expect(calendarDays(DateTime(2026, 3, 28), DateTime(2026, 3, 30)), 2);
    expect(calendarDays(DateTime(2026, 3, 7), DateTime(2026, 3, 9)), 2);
    expect(calendarDays(DateTime(2026, 11, 9), DateTime(2026, 11, 9)), 0);
    final op = ProductionBoardOperation.fromJson(
      _op('o7', 'PO-7', 'Weld', 'c1', 9, 9),
    ).toJson();
    final across = ProductionBoardOperation.fromJson({
      ...op,
      'planned_start': '2026-10-24',
      'planned_end': '2026-10-26',
    });
    expect(
      moveBody(across, 'c1', DateTime(2026, 10, 24)).plannedEnd,
      DateTime(2026, 10, 26),
    );
    // A block fills the same part of its first and last day however long the days are.
    expect(atMinute(DateTime(2026, 10, 25), workCentreAxisStart).hour, 6);
    expect(atMinute(DateTime(2026, 10, 25), workCentreAxisEnd).hour, 18);
  });

  testWidgets(
    'changing the week waits for the new week and keeps the week buttons',
    (tester) async {
      final hold = Completer<void>();
      final http = _server(holdReload: hold);
      await _pump(tester, http);
      expect(find.byType(ResourceBoard), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('wc-next')));
      await tester.pump();
      // The old week is not shown under the new week's dates.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(ResourceBoard), findsNothing);
      expect(find.byKey(const ValueKey('wc-next')), findsOneWidget);
      expect(find.byKey(const ValueKey('wc-prev')), findsOneWidget);
      expect(find.byKey(const ValueKey('wc-today')), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byType(ResourceBoard), findsOneWidget);
      final froms = http.queries.where((q) => q.containsKey('from')).toList();
      expect(froms.last['from'], startsWith('2026-11-16'));
      expect(froms.last['to'], startsWith('2026-11-22'));
    },
  );

  testWidgets('leaving the page while a drop is being checked does nothing', (
    tester,
  ) async {
    final hold = Completer<void>();
    final http = _server(holdMoves: hold);
    await _pump(tester, http);
    final g = await _dragCutToWeldWednesday(tester);
    await g.up();
    await tester.pump();
    // The page goes away while the check is still on its way.
    await tester.pumpWidget(const SizedBox.shrink());
    hold.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_realMoves(http), isEmpty);
  });

  testWidgets('a refused move names its conflicts', (tester) async {
    // Another planner made the day full between the check and the move: the server refuses with
    // its report and the board says why.
    late FakeHttp http;
    http = FakeHttp({
      'GET /api/v1/me': (_) =>
          meJson(const ['production.read', 'production.write']),
      'GET /api/v1/production/planning-board': (_) => _board(),
      'PUT /api/v1/production-orders/p-PO-1/operations/o1/move': (_) {
        final q = http.queries.last;
        final overload = [
          {
            'kind': 'overload',
            'severity': q['dry_run'] == true ? 'warning' : 'error',
            'message_key': 'production.conflict.overload',
            'day': _d(11),
          },
        ];
        return q['dry_run'] == true
            ? {'applied': false, 'conflicts': overload, 'order': null}
            : FakeStatus(409, {
                'applied': false,
                'conflicts': overload,
                'order': null,
              });
      },
    });
    await _pump(tester, http);
    final g = await _dragCutToWeldWednesday(tester);
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('Wed 11 Nov would be overloaded.'), findsOneWidget);
  });

  testWidgets('a phone gets a list per work centre', (tester) async {
    final http = _server();
    await _pump(tester, http, size: const Size(400, 900));
    expect(find.byKey(const ValueKey('wc-agenda')), findsOneWidget);
    expect(find.byType(ResourceBoard), findsNothing);
    expect(find.text('SAW · Work centre SAW'), findsOneWidget);
  });
}
