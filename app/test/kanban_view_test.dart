import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/framework/views/kanban/kanban_config.dart';
import 'package:tradocraft_app/framework/views/kanban/kanban_controller.dart';
import 'package:tradocraft_app/framework/views/kanban/kanban_view.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

/// A card of the test board.
class Card1 {
  const Card1(this.id, this.title);
  final String id;
  final String title;
}

class Fixture {
  Fixture({Map<String, List<Card1>>? data, this.pageSize = 50})
    : data =
          data ??
          {
            'todo': [const Card1('a', 'Alpha'), const Card1('b', 'Beta')],
            'doing': [const Card1('c', 'Gamma')],
            'done': [],
          };

  final Map<String, List<Card1>> data;
  final int pageSize;
  final moves = <(String, String)>[];
  MoveResult result = MoveResult.moved;
  Object? refuse;
  Completer<void>? gate;
  final failing = <String>{};
  var summaryCalls = 0;
  final loads = <(String, int)>[];

  KanbanConfig<Card1> config({bool create = false, bool reload = false}) =>
      KanbanConfig<Card1>(
        reloadAfterMove: reload,
        columns: const [
          KanbanColumnDef('todo', 'To do'),
          KanbanColumnDef('doing', 'Doing'),
          KanbanColumnDef('done', 'Done'),
        ],
        pageSize: pageSize,
        idOf: (c) => c.id,
        cardBuilder: (_, c) => Text(c.title),
        loadColumn: (col, offset, limit) async {
          loads.add((col, offset));
          if (failing.contains(col)) throw 'boom';
          final all = data[col]!;
          return KanbanPage(all.skip(offset).take(limit).toList(), all.length);
        },
        loadSummaries: () async {
          summaryCalls++;
          return {
            for (final e in data.entries) e.key: '${e.value.length} cards',
          };
        },
        move: (c, to) async {
          moves.add((c.id, to));
          await gate?.future;
          if (refuse != null) throw refuse!;
          if (result == MoveResult.moved) {
            for (final l in data.values) {
              l.removeWhere((x) => x.id == c.id);
            }
            data[to]!.insert(0, c);
          }
          return result;
        },
        onOpen: (_) {},
        onCreate: create ? (_) async {} : null,
      );
}

Future<KanbanController<Card1>> _pump(
  WidgetTester t,
  Fixture f, {
  bool create = false,
}) async {
  t.view.physicalSize = const Size(1200, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final controller = KanbanController<Card1>(f.config(create: create));
  addTearDown(controller.dispose);
  await t.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: KanbanView<Card1>(controller: controller)),
    ),
  );
  controller.load();
  await t.pumpAndSettle();
  return controller;
}

Finder _card(String id) => find.byKey(ValueKey('kanban-card-$id'));
Finder _col(String id) => find.byKey(ValueKey('kanban-column-$id'));
Finder _inColumn(String col, String id) =>
    find.descendant(of: _col(col), matching: _card(id));

Future<void> _moveByMenu(WidgetTester t, String id, String to) async {
  await t.tap(find.byKey(ValueKey('kanban-menu-$id')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(ValueKey('kanban-move-$id-$to')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows every column with its count, summary and cards', (
    t,
  ) async {
    await _pump(t, Fixture());
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // to do
    expect(find.text('2 cards'), findsOneWidget);
    expect(_inColumn('todo', 'a'), findsOneWidget);
    expect(_inColumn('doing', 'c'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-empty-done')), findsOneWidget);
    expect(find.text('Nothing here'), findsOneWidget);
  });

  testWidgets('a card is moved by its menu, at once, and the numbers follow', (
    t,
  ) async {
    final f = Fixture();
    final gate = f.gate = Completer<void>();
    await _pump(t, f);
    expect(f.summaryCalls, 1);
    await _moveByMenu(t, 'a', 'doing');
    // the server has not answered yet: the card is already in its new column
    expect(f.moves, [('a', 'doing')]);
    expect(_inColumn('doing', 'a'), findsOneWidget);
    expect(_inColumn('todo', 'a'), findsNothing);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('kanban-count-todo'))).data,
      '1',
    );
    expect(
      t.widget<Text>(find.byKey(const ValueKey('kanban-count-doing'))).data,
      '2',
    );
    gate.complete();
    await t.pumpAndSettle();
    expect(_inColumn('doing', 'a'), findsOneWidget);
    expect(f.summaryCalls, 2, reason: 'the sums are read again after a move');
    expect(find.byKey(const ValueKey('kanban-error')), findsNothing);
  });

  testWidgets('a card is moved by dragging it onto another column', (t) async {
    final f = Fixture();
    await _pump(t, f);
    final from = t.getCenter(_card('a'));
    final to = t.getCenter(_col('done'));
    final g = await t.startGesture(from);
    await t.pump(
      const Duration(milliseconds: 250),
    ); // the hold that picks it up
    await g.moveTo(to);
    await t.pump();
    await g.up();
    await t.pumpAndSettle();
    expect(f.moves, [('a', 'done')]);
    expect(_inColumn('done', 'a'), findsOneWidget);
  });

  testWidgets('dropping a card on its own column moves nothing', (t) async {
    final f = Fixture();
    await _pump(t, f);
    final g = await t.startGesture(t.getCenter(_card('a')));
    await t.pump(const Duration(milliseconds: 250));
    await g.moveTo(t.getCenter(_col('todo')) + const Offset(0, 100));
    await g.up();
    await t.pumpAndSettle();
    expect(f.moves, isEmpty);
    expect(_inColumn('todo', 'a'), findsOneWidget);
  });

  testWidgets('a refused move puts the card back and says why', (t) async {
    final f = Fixture()..refuse = const KanbanMoveRefused('Not allowed');
    await _pump(t, f);
    await _moveByMenu(t, 'a', 'done');
    expect(_inColumn('todo', 'a'), findsOneWidget);
    expect(_inColumn('done', 'a'), findsNothing);
    expect(find.text('Not allowed'), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('kanban-count-todo'))).data,
      '2',
    );
    // the card went back to its place, first in the column
    final order = [
      for (final id in ['a', 'b']) t.getTopLeft(_card(id)).dy,
    ];
    expect(order[0], lessThan(order[1]));
  });

  testWidgets('a cancelled move puts the card back without an error', (
    t,
  ) async {
    final f = Fixture()..result = MoveResult.cancelled;
    await _pump(t, f);
    await _moveByMenu(t, 'b', 'doing');
    expect(f.moves, [('b', 'doing')]);
    expect(_inColumn('todo', 'b'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-error')), findsNothing);
  });

  testWidgets('the error can be dismissed', (t) async {
    final f = Fixture()..refuse = 'nope';
    await _pump(t, f);
    await _moveByMenu(t, 'a', 'done');
    expect(find.byKey(const ValueKey('kanban-error')), findsOneWidget);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('kanban-error')), findsNothing);
  });

  testWidgets('a column that fails shows a retry and the others still load', (
    t,
  ) async {
    final f = Fixture()..failing.add('doing');
    await _pump(t, f);
    expect(_inColumn('todo', 'a'), findsOneWidget);
    expect(find.text('This column could not be loaded.'), findsOneWidget);
    f.failing.clear();
    await t.tap(find.byKey(const ValueKey('kanban-retry-doing')));
    await t.pumpAndSettle();
    expect(_inColumn('doing', 'c'), findsOneWidget);
  });

  testWidgets('a long column loads more on request, without duplicates', (
    t,
  ) async {
    final f = Fixture(
      pageSize: 2,
      data: {
        'todo': [for (var i = 1; i <= 5; i++) Card1('t$i', 'Task $i')],
        'doing': [],
        'done': [],
      },
    );
    await _pump(t, f);
    expect(find.text('Show 3 more'), findsOneWidget);
    expect(_card('t3'), findsNothing);
    // a card moved in meanwhile that the server also lists on the next page
    await t.tap(find.byKey(const ValueKey('kanban-more-todo')));
    await t.pumpAndSettle();
    expect(f.loads.where((l) => l.$1 == 'todo').map((l) => l.$2), [0, 2]);
    expect(_card('t3'), findsOneWidget);
    expect(find.text('Show 1 more'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kanban-more-todo')));
    await t.pumpAndSettle();
    expect(_card('t5'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-more-todo')), findsNothing);
  });

  testWidgets('the add button shows only where the config allows it', (
    t,
  ) async {
    await _pump(t, Fixture(), create: true);
    expect(find.byKey(const ValueKey('kanban-add-todo')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanban-add-done')), findsOneWidget);
  });

  testWidgets('cards are labelled for screen readers', (t) async {
    final h = t.ensureSemantics();
    await _pump(t, Fixture());
    expect(find.bySemanticsLabel(RegExp(r'^To do, 2')), findsOneWidget);
    h.dispose();
  });

  group('controller', () {
    test('a move onto the column the card is in does nothing', () async {
      final f = Fixture();
      final c = KanbanController<Card1>(f.config());
      addTearDown(c.dispose);
      await c.load();
      expect(await c.move(const Card1('a', 'Alpha'), 'todo', 'todo'), isFalse);
      expect(f.moves, isEmpty);
    });

    test('the same card is not moved twice at once', () async {
      final f = Fixture()..gate = Completer<void>();
      final c = KanbanController<Card1>(f.config());
      addTearDown(c.dispose);
      await c.load();
      const card = Card1('a', 'Alpha');
      final first = c.move(card, 'todo', 'doing');
      expect(c.isMoving(card), isTrue);
      expect(await c.move(card, 'doing', 'done'), isFalse);
      f.gate!.complete();
      expect(await first, isTrue);
      expect(f.moves.length, 1);
    });

    test('after a move the card is found where the board shows it', () async {
      final f = Fixture();
      final c = KanbanController<Card1>(f.config());
      addTearDown(c.dispose);
      await c.load();
      const card = Card1(
        'a',
        'Alpha',
      ); // the item itself never learns its new column
      expect(await c.move(card, 'todo', 'doing'), isTrue);
      expect(await c.move(card, 'doing', 'done'), isTrue);
      expect(c.columns['done']!.items.map((i) => i.id), ['a']);
      expect(c.columns['doing']!.items.map((i) => i.id), ['c']);
    });

    test('an answer that arrives after a reload is dropped', () async {
      final gate = Completer<void>();
      var first = true;
      final base = Fixture().config();
      final c = KanbanController<Card1>(
        KanbanConfig<Card1>(
          columns: base.columns,
          idOf: base.idOf,
          cardBuilder: base.cardBuilder,
          move: base.move,
          loadColumn: (col, offset, limit) async {
            if (first && col == 'todo') {
              first = false;
              await gate.future;
              return const KanbanPage([Card1('old', 'Stale')], 1);
            }
            return const KanbanPage([Card1('new', 'Fresh')], 1);
          },
        ),
      );
      addTearDown(c.dispose);
      final slow = c.load();
      await c.load(); // a newer load finishes first
      gate.complete();
      await slow;
      expect(c.columns['todo']!.items.map((i) => i.id), ['new']);
    });

    // A config whose loads can be held back, to put answers in any order.
    KanbanConfig<Card1> gated(
      Map<String, List<Card1>> data,
      List<(String, int)> loads, {
      Future<void> Function(String col, int offset)? hold,
      Future<MoveResult> Function(Card1, String)? move,
      Future<Map<String, String>> Function()? summaries,
    }) => KanbanConfig<Card1>(
      columns: const [
        KanbanColumnDef('todo', 'To do'),
        KanbanColumnDef('doing', 'Doing'),
      ],
      pageSize: 2,
      idOf: (c) => c.id,
      cardBuilder: (_, c) => Text(c.title),
      loadColumn: (col, offset, limit) async {
        loads.add((col, offset));
        await hold?.call(col, offset);
        final all = data[col]!;
        return KanbanPage(all.skip(offset).take(limit).toList(), all.length);
      },
      loadSummaries: summaries,
      move: move ?? (c, to) async => MoveResult.moved,
    );

    Map<String, List<Card1>> five() => {
      'todo': [for (var i = 1; i <= 5; i++) Card1('t$i', 'Task $i')],
      'doing': [const Card1('d1', 'Doing 1')],
    };

    test('with reloadAfterMove a worked move reads both columns again, a refused one does not', () async {
      final f = Fixture();
      final c = KanbanController<Card1>(f.config(reload: true));
      addTearDown(c.dispose);
      await c.load();
      f.loads.clear();
      expect(await c.move(const Card1('a', 'Alpha'), 'todo', 'doing'), isTrue);
      expect({for (final l in f.loads) l.$1}, {'todo', 'doing'});
      // what the server holds is what is shown: a first in doing, c still there
      expect(c.columns['doing']!.items.map((i) => i.id), ['a', 'c']);
      f.loads.clear();
      f.refuse = 'no';
      expect(await c.move(const Card1('b', 'Beta'), 'todo', 'done'), isFalse);
      expect(f.loads, isEmpty, reason: 'nothing changed on the server');
      f.refuse = null;
      f.result = MoveResult.cancelled;
      expect(await c.move(const Card1('b', 'Beta'), 'todo', 'done'), isFalse);
      expect(f.loads, isEmpty);
    });

    test('without it a worked move reads no column again', () async {
      final f = Fixture();
      final c = KanbanController<Card1>(f.config());
      addTearDown(c.dispose);
      await c.load();
      f.loads.clear();
      await c.move(const Card1('a', 'Alpha'), 'todo', 'doing');
      expect(f.loads, isEmpty);
    });

    test(
      'after a reload the next page starts from what the server holds',
      () async {
        final f = Fixture(
          pageSize: 2,
          data: {
            'todo': [for (var i = 1; i <= 5; i++) Card1('t$i', 'Task $i')],
            'doing': [],
            'done': [],
          },
        );
        final c = KanbanController<Card1>(f.config(reload: true));
        addTearDown(c.dispose);
        await c.load(); // t1 t2 of 5
        await c.move(
          const Card1('t1', 'Task 1'),
          'todo',
          'doing',
        ); // server: t2 t3 t4 t5 left
        expect(c.columns['todo']!.items.map((i) => i.id), ['t2', 't3']);
        f.loads.clear();
        await c.loadMore('todo');
        expect(f.loads, [('todo', 2)]);
        expect(c.columns['todo']!.items.map((i) => i.id), [
          't2',
          't3',
          't4',
          't5',
        ]);
      },
    );

    test(
      'a move finishing after a reload reads the two columns again',
      () async {
        final data = five();
        final loads = <(String, int)>[];
        final gate = Completer<void>();
        final c = KanbanController<Card1>(
          gated(
            data,
            loads,
            move: (card, to) async {
              await gate.future;
              data['todo']!.removeWhere((x) => x.id == card.id);
              data['doing']!.insert(0, card);
              return MoveResult.moved;
            },
          ),
        );
        addTearDown(c.dispose);
        await c.load();
        final moving = c.move(const Card1('t1', 'Task 1'), 'todo', 'doing');
        await c.load(); // reloaded before the server applied the move: t1 is still in todo
        expect(c.columns['todo']!.items.map((i) => i.id), contains('t1'));
        loads.clear();
        gate.complete();
        expect(await moving, isTrue);
        // the new state is read, not the old optimistic one replayed
        expect(loads.map((l) => l.$1).toSet(), {'todo', 'doing'});
        expect(
          c.columns['todo']!.items.map((i) => i.id),
          isNot(contains('t1')),
        );
        expect(c.columns['doing']!.items.map((i) => i.id), contains('t1'));
      },
    );

    test('only the latest summary request counts', () async {
      final slow = Completer<Map<String, String>>();
      var call = 0;
      final c = KanbanController<Card1>(
        gated(
          five(),
          [],
          summaries: () {
            call++;
            return call == 1 ? slow.future : Future.value({'todo': 'new'});
          },
        ),
      );
      addTearDown(c.dispose);
      final first = c.refreshSummaries();
      await c.refreshSummaries();
      expect(c.summaries['todo'], 'new');
      slow.complete({'todo': 'old'}); // the older answer arrives last
      await first;
      expect(c.summaries['todo'], 'new');
    });

    test(
      'the next page starts at the server offset, not at the cards on screen',
      () async {
        final data = five();
        final loads = <(String, int)>[];
        final gate = Completer<void>();
        final c = KanbanController<Card1>(
          gated(
            data,
            loads,
            move: (card, to) async {
              await gate.future;
              return MoveResult.moved;
            },
          ),
        );
        addTearDown(c.dispose);
        await c.load(); // todo: t1 t2 of 5
        // a card goes into todo (optimistically): three cards on screen, two read from the server
        final moving = c.move(const Card1('d1', 'Doing 1'), 'doing', 'todo');
        expect(c.columns['todo']!.items.length, 3);
        loads.clear();
        await c.loadMore('todo');
        expect(loads, [('todo', 2)], reason: 'offset 3 would skip t3');
        expect(c.columns['todo']!.items.map((i) => i.id), [
          'd1',
          't1',
          't2',
          't3',
          't4',
        ]);
        gate.complete();
        await moving;
      },
    );

    test('a page arriving during a move keeps the move in the total, and a refusal restores it', () async {
      final data = five();
      final gate = Completer<void>();
      final c = KanbanController<Card1>(
        gated(
          data,
          [],
          move: (card, to) async {
            await gate.future;
            throw 'refused';
          },
        ),
      );
      addTearDown(c.dispose);
      await c.load();
      expect(c.columns['todo']!.total, 5);
      final moving = c.move(const Card1('d1', 'Doing 1'), 'doing', 'todo');
      expect(c.columns['todo']!.total, 6);
      await c.loadMore('todo'); // the server still says 5
      expect(c.columns['todo']!.total, 6);
      gate.complete();
      expect(await moving, isFalse);
      expect(
        c.columns['todo']!.total,
        5,
        reason: 'back to what the server holds',
      );
      expect(c.columns['doing']!.total, 1);
    });

    test(
      'a reload frees a column whose next page was still on its way',
      () async {
        final data = five();
        final loads = <(String, int)>[];
        final gate = Completer<void>();
        var hold = false;
        final c = KanbanController<Card1>(
          gated(
            data,
            loads,
            hold: (col, offset) async {
              if (hold) await gate.future;
            },
          ),
        );
        addTearDown(c.dispose);
        await c.load();
        hold = true;
        final stuck = c.loadMore('todo');
        expect(c.columns['todo']!.loadingMore, isTrue);
        hold = false;
        await c.load(); // a new load: the old request no longer owns the flag
        expect(c.columns['todo']!.loadingMore, isFalse);
        await c.loadMore('todo'); // the new load can page at once
        expect(c.columns['todo']!.items.length, 4);
        gate.complete();
        await stuck; // the old answer arrives and changes nothing
        expect(c.columns['todo']!.items.length, 4);
        expect(c.columns['todo']!.loadingMore, isFalse);
      },
    );
  });

  testWidgets('a column emptied of loaded cards still offers the rest', (
    t,
  ) async {
    final f = Fixture(
      pageSize: 1,
      data: {
        'todo': [
          const Card1('a', 'Alpha'),
          const Card1('b', 'Beta'),
          const Card1('c', 'Gamma'),
        ],
        'doing': [],
        'done': [],
      },
    );
    await _pump(t, f);
    expect(find.byKey(const ValueKey('kanban-more-todo')), findsOneWidget);
    await _moveByMenu(t, 'a', 'doing'); // the only loaded card leaves
    expect(_card('a'), findsOneWidget); // now in doing
    expect(
      find.byKey(const ValueKey('kanban-empty-todo')),
      findsNothing,
      reason: 'two more are on the server',
    );
    expect(find.byKey(const ValueKey('kanban-more-todo')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('kanban-more-todo')));
    await t.pumpAndSettle();
    expect(_inColumn('todo', 'b'), findsOneWidget);
  });
}
