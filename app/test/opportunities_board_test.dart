import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/opportunities/opportunities_page.dart';
import 'package:tradocraft_app/l10n/app_localizations_en.dart';
import 'package:tradocraft_app/l10n/app_localizations_nl.dart';
import 'package:tradocraft_app/l10n/l10n.dart';

import 'fake_http.dart';

Map<String, Object?> _opp(
  String id,
  String stage,
  String title,
  String value,
) => {
  'id': id,
  'number': 'OPP-$id',
  'title': title,
  'customer_id': 'c2',
  'customer_name': 'Bêta Industrie SA',
  'owner_user_id': 'u1',
  'owner_name': 'Owner',
  'stage': stage,
  'expected_value': value,
  'probability': 20,
  'expected_close': '2027-03-15',
  'notes': '',
  'created_at': '2027-01-01T00:00:00Z',
  'updated_at': '2027-01-01T00:00:00Z',
};

/// A fake server that answers the opportunity list by its `stage` and `q` parameters.
class _Server extends FakeHttp {
  _Server(super.routes);

  final data = <String, List<Map<String, Object?>>>{
    'lead': [_opp('1', 'lead', 'Tower A', '25000')],
    'qualified': [_opp('2', 'qualified', 'Tower B', '9000')],
    'proposal': [],
    'negotiation': [],
    'won': [],
    'lost': [_opp('3', 'lost', 'Old deal', '500')],
  };
  final listQueries = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) {
    if (o.method == 'GET' && o.path == '/api/v1/opportunities') {
      listQueries.add(Map.of(o.queryParameters));
      final stage = o.queryParameters['stage'] as String?;
      final q = (o.queryParameters['q'] as String?)?.toLowerCase();
      final rows = [
        for (final r in data[stage] ?? const <Map<String, Object?>>[])
          if (q == null || '${r['title']}'.toLowerCase().contains(q)) r,
      ];
      final saved = routes['GET /api/v1/opportunities'];
      routes['GET /api/v1/opportunities'] = (_) => {
        'items': rows,
        'total': rows.length,
      };
      final answer = super.fetch(o, body, cancel);
      if (saved != null) routes['GET /api/v1/opportunities'] = saved;
      return answer;
    }
    return super.fetch(o, body, cancel);
  }
}

_Server _server({
  List<String> permissions = const [
    'opportunities.read',
    'opportunities.write',
  ],
}) {
  final s = _Server({
    'GET /api/v1/me': (_) => meJson(permissions),
    'GET /api/v1/opportunities': (_) => {'items': <Object?>[], 'total': 0},
    'GET /api/v1/opportunities/pipeline': (_) => [
      for (final s in [
        'lead',
        'qualified',
        'proposal',
        'negotiation',
        'won',
        'lost',
      ])
        {
          'stage': s,
          'count': s == 'lead' ? 1 : 0,
          'total_value': s == 'lead' ? '25000' : '0',
          'weighted_value': s == 'lead' ? '5000' : '0',
        },
    ],
    'GET /api/v1/opportunities/1': (_) => _opp('1', 'lead', 'Tower A', '25000'),
  });
  // Entering a stage resets the probability to the stage's default, as the server does.
  const defaults = {
    'lead': 10,
    'qualified': 25,
    'proposal': 50,
    'negotiation': 75,
    'won': 100,
    'lost': 0,
  };
  for (final id in ['1', '2', '3']) {
    s.routes['POST /api/v1/opportunities/$id/stage'] = (b) {
      final stage = (b as Map)['stage'] as String;
      Map<String, Object?>? found;
      for (final list in s.data.values) {
        for (final r in [...list]) {
          if (r['id'] == id) {
            found = r;
            list.remove(r);
          }
        }
      }
      final moved = {...?found, 'stage': stage, 'probability': defaults[stage]};
      s.data[stage]!.insert(0, moved);
      return moved;
    };
  }
  return s;
}

Future<void> _pump(WidgetTester t, _Server http) async {
  t.view.physicalSize = const Size(1500, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: OpportunitiesPage()),
            ),
            GoRoute(
              path: '/opportunities/:id',
              builder: (_, s) => Text('OPEN ${s.pathParameters['id']}'),
            ),
          ],
        ),
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _showBoard(WidgetTester t) async {
  await t.tap(
    find.descendant(
      of: find.byKey(const ValueKey('opportunities-view')),
      matching: find.text('Board'),
    ),
  );
  await t.pumpAndSettle();
}

Finder _card(String id) => find.byKey(ValueKey('kanban-card-$id'));
Finder _in(String stage, String id) => find.descendant(
  of: find.byKey(ValueKey('kanban-column-$stage')),
  matching: _card(id),
);

void main() {
  testWidgets('the list stays the default, the board is one switch away', (
    t,
  ) async {
    await _pump(t, _server());
    expect(find.byKey(const ValueKey('kanban-column-lead')), findsNothing);
    await _showBoard(t);
    for (final s in [
      'lead',
      'qualified',
      'proposal',
      'negotiation',
      'won',
      'lost',
    ]) {
      expect(
        find.byKey(ValueKey('kanban-column-$s')),
        findsOneWidget,
        reason: s,
      );
    }
  });

  testWidgets(
    'every stage lists its own opportunities with the pipeline sums',
    (t) async {
      final http = _server();
      await _pump(t, http);
      await _showBoard(t);
      expect(_in('lead', '1'), findsOneWidget);
      expect(_in('qualified', '2'), findsOneWidget);
      expect(_in('lost', '3'), findsOneWidget);
      expect(find.text('Tower A'), findsOneWidget);
      // the lead column carries the sum and the weighted sum of the pipeline summary
      expect(find.byKey(const ValueKey('kanban-summary-lead')), findsOneWidget);
      expect(
        t.widget<Text>(find.byKey(const ValueKey('kanban-summary-lead'))).data,
        allOf(contains('25'), contains('5')),
      );
      // the board asks for 50 per column and for each stage
      final stages = http.listQueries.map((q) => q['stage']).toSet();
      expect(
        stages.containsAll([
          'lead',
          'qualified',
          'proposal',
          'negotiation',
          'won',
          'lost',
        ]),
        isTrue,
      );
      expect(http.listQueries.every((q) => q['limit'] == 50), isTrue);
    },
  );

  testWidgets('moving a card to another stage posts the stage', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(find.byKey(const ValueKey('kanban-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-1-proposal')));
    await t.pumpAndSettle();
    expect(http.requests, contains('POST /api/v1/opportunities/1/stage'));
    expect(
      http.bodies['POST /api/v1/opportunities/1/stage'],
      containsPair('stage', 'proposal'),
    );
    expect(_in('proposal', '1'), findsOneWidget);
  });

  testWidgets('after a move the card shows the probability the server set', (
    t,
  ) async {
    await _pump(t, _server());
    await _showBoard(t);
    expect(
      find.descendant(of: _card('1'), matching: find.textContaining('20 %')),
      findsOneWidget,
    );
    await t.tap(find.byKey(const ValueKey('kanban-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-1-proposal')));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: _card('1'), matching: find.textContaining('50 %')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _card('1'), matching: find.textContaining('20 %')),
      findsNothing,
    );
  });

  testWidgets('moving to lost asks for a reason first', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(find.byKey(const ValueKey('kanban-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-1-lost')));
    await t.pumpAndSettle();
    // the card is already in the lost column while the reason is asked
    expect(find.text('Mark as lost'), findsWidgets);
    await t.enterText(find.byType(TextField).last, 'Too expensive');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(http.bodies['POST /api/v1/opportunities/1/stage'], {
      'stage': 'lost',
      'lost_reason': 'Too expensive',
    });
    expect(_in('lost', '1'), findsOneWidget);
  });

  testWidgets('backing out of the reason dialog puts the card back', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(find.byKey(const ValueKey('kanban-menu-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-1-lost')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(
      http.requests,
      isNot(contains('POST /api/v1/opportunities/1/stage')),
    );
    expect(_in('lead', '1'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-error')), findsNothing);
  });

  testWidgets(
    'an empty reason is refused: the card goes back and the board says why',
    (t) async {
      final http = _server();
      await _pump(t, http);
      await _showBoard(t);
      await t.tap(find.byKey(const ValueKey('kanban-menu-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('kanban-move-1-lost')));
      await t.pumpAndSettle();
      await t.tap(find.text('OK')); // nothing typed
      await t.pumpAndSettle();
      expect(
        http.requests,
        isNot(contains('POST /api/v1/opportunities/1/stage')),
      );
      expect(_in('lead', '1'), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-error')), findsOneWidget);
    },
  );

  testWidgets('a server refusal puts the card back and shows the message', (
    t,
  ) async {
    final http = _server();
    http.routes['POST /api/v1/opportunities/2/stage'] = (_) =>
        const FakeStatus(422, {'error': 'validation', 'message': 'Not now'});
    await _pump(t, http);
    await _showBoard(t);
    await t.tap(find.byKey(const ValueKey('kanban-menu-2')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('kanban-move-2-negotiation')));
    await t.pumpAndSettle();
    expect(_in('qualified', '2'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('searching filters every column', (t) async {
    final http = _server();
    await _pump(t, http);
    await _showBoard(t);
    await t.enterText(find.byKey(const ValueKey('board-search')), 'tower b');
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(http.listQueries.last['q'], 'tower b');
    expect(_in('qualified', '2'), findsOneWidget);
    expect(_card('1'), findsNothing);
  });

  testWidgets('a card opens the opportunity', (t) async {
    await _pump(t, _server());
    await _showBoard(t);
    await t.tap(find.text('Tower A'));
    await t.pumpAndSettle();
    expect(find.text('OPEN 1'), findsOneWidget);
  });

  testWidgets(
    '"+" is offered on open stages only, and only with write access',
    (t) async {
      await _pump(t, _server());
      await _showBoard(t);
      for (final s in ['lead', 'qualified', 'proposal', 'negotiation']) {
        expect(
          find.byKey(ValueKey('kanban-add-$s')),
          findsOneWidget,
          reason: s,
        );
      }
      expect(find.byKey(const ValueKey('kanban-add-won')), findsNothing);
      expect(find.byKey(const ValueKey('kanban-add-lost')), findsNothing);
    },
  );

  testWidgets('without write access there is no "+"', (t) async {
    await _pump(t, _server(permissions: ['opportunities.read']));
    await _showBoard(t);
    expect(find.byKey(const ValueKey('kanban-add-lead')), findsNothing);
  });

  testWidgets('another language retitles the columns and keeps the cards', (
    t,
  ) async {
    t.view.physicalSize = const Size(1500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final http = _server();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: OpportunitiesPage()),
        ),
      ],
    );
    Widget app(Locale locale) => ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp.router(
        routerConfig: router,
        locale: locale,
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await t.pumpWidget(app(const Locale('en')));
    await t.pumpAndSettle();
    await _showBoard(t);
    final en = AppLocalizationsEn().opportunityStage('qualified');
    final nl = AppLocalizationsNl().opportunityStage('qualified');
    expect(en, isNot(nl));
    expect(find.text(en), findsWidgets);
    final before = http.requests
        .where((r) => r == 'GET /api/v1/opportunities')
        .length;
    final pipelineBefore = http.requests
        .where((r) => r == 'GET /api/v1/opportunities/pipeline')
        .length;
    await t.pumpWidget(app(const Locale('nl')));
    await t.pumpAndSettle();
    expect(find.text(nl), findsWidgets);
    expect(find.text(en), findsNothing);
    expect(_in('qualified', '2'), findsOneWidget, reason: 'the cards stay');
    expect(
      http.requests.where((r) => r == 'GET /api/v1/opportunities').length,
      before,
      reason: 'no reload of the cards',
    );
    expect(
      http.requests
          .where((r) => r == 'GET /api/v1/opportunities/pipeline')
          .length,
      pipelineBefore + 1,
      reason: 'the sums are read again, their text has a translated word',
    );
  });

  testWidgets('the "+" follows the user rights when they change', (t) async {
    t.view.physicalSize = const Size(1500, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var permissions = ['opportunities.read'];
    final http = _server();
    http.routes['GET /api/v1/me'] = (_) => meJson(permissions);
    final container = ProviderContainer(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(
                path: '/',
                builder: (_, _) => const Scaffold(body: OpportunitiesPage()),
              ),
            ],
          ),
          locale: const Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );
    await t.pumpAndSettle();
    await _showBoard(t);
    expect(find.byKey(const ValueKey('kanban-add-lead')), findsNothing);
    permissions = ['opportunities.read', 'opportunities.write'];
    container.invalidate(meProvider);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kanban-add-lead')), findsOneWidget);
    expect(_in('lead', '1'), findsOneWidget, reason: 'the cards stay');
    permissions = ['opportunities.read'];
    container.invalidate(meProvider);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kanban-add-lead')), findsNothing);
  });
}
