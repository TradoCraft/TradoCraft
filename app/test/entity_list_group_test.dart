import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/framework/data/repository.dart';
import 'package:tradocraft_app/framework/search/filter_model.dart';
import 'package:tradocraft_app/framework/search/group_model.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/entity_list.dart';

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

const _filters = [
  FilterDef(
    key: 'status',
    label: 'Status',
    options: [('draft', 'Draft'), ('sent', 'Sent'), ('won', 'Won')],
  ),
  FilterDef(
    key: 'country',
    label: 'Country',
    options: [('de', 'Germany'), ('nl', 'Netherlands')],
  ),
];

const _groups = [GroupDef('status', 'Status'), GroupDef('country', 'Country')];

class _Row {
  const _Row(this.name, this.status, this.country);
  final String name;
  final String status;
  final String country;
}

/// 60 draft rows, 2 sent rows, 1 row of an unknown status.
final _data = [
  for (var i = 0; i < 60; i++)
    _Row('Draft $i', 'draft', i.isEven ? 'de' : 'nl'),
  const _Row('Sent 0', 'sent', 'de'),
  const _Row('Sent 1', 'sent', 'nl'),
  const _Row('Odd 0', 'odd', 'de'),
];

class _Fake {
  final queries = <ListQuery>[];
  final groupCalls = <(ListQuery, String)>[];
  Completer<void>? gate;
  Object? failNext;

  Iterable<_Row> _hits(ListQuery q) => _data.where((r) {
    if (q.search != null && !r.name.contains(q.search!)) return false;
    final s = q.filters['status'] as Set<String>?;
    final c = q.filters['country'] as Set<String>?;
    return (s == null || s.contains(r.status)) &&
        (c == null || c.contains(r.country));
  });

  Future<(List<_Row>, int)> load(ListQuery q) async {
    queries.add(q);
    if (gate != null) await gate!.future;
    final e = failNext;
    if (e != null) {
      failNext = null;
      throw e;
    }
    final hits = _hits(q).toList();
    return (hits.skip(q.offset).take(q.limit).toList(), hits.length);
  }

  Future<List<GroupBucket>> loadGroups(ListQuery q, String by) async {
    groupCalls.add((q, by));
    final counts = <String, int>{};
    for (final r in _hits(q)) {
      final v = by == 'status' ? r.status : r.country;
      counts[v] = (counts[v] ?? 0) + 1;
    }
    final keys = counts.keys.toList()..sort();
    return [for (final k in keys) GroupBucket(k, counts[k]!)];
  }
}

Future<_Fake> _pump(
  WidgetTester t, {
  Size size = const Size(1200, 800),
  bool selectable = false,
  void Function(List<_Row>)? onSelection,
  String? prefsKey,
  KvStore? store,
  _Fake? fake,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final f = fake ?? _Fake();
  await t.pumpWidget(
    _app(
      EntityList<_Row>(
        title: 'Things',
        loadQuery: f.load,
        columns: [EntityColumn<_Row>('Name', (r) => r.name)],
        filterDefs: _filters,
        groupDefs: _groups,
        loadGroups: f.loadGroups,
        onOpen: (r) async => null,
        selectable: selectable,
        idOf: selectable ? (r) => r.name : null,
        onSelectionChanged: onSelection,
        prefsKey: prefsKey,
        prefsStore: store,
      ),
    ),
  );
  await t.pumpAndSettle();
  return f;
}

Future<void> _menu(WidgetTester t) async {
  if (find.text('Group by').evaluate().isNotEmpty) return;
  await t.tap(find.byTooltip('Filters'));
  await t.pumpAndSettle();
}

Future<void> _groupBy(WidgetTester t, String label) async {
  await _menu(t);
  await t.tap(find.widgetWithText(RadioMenuButton<String?>, label));
  await t.pumpAndSettle();
}

Future<void> _closeMenu(WidgetTester t) async {
  await t.tapAt(const Offset(5, 5));
  await t.pumpAndSettle();
}

Set<String>? _f(ListQuery q, String key) => q.filters[key] as Set<String>?;

void main() {
  testWidgets('without groupDefs nothing changes', (t) async {
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final f = _Fake();
    await t.pumpWidget(
      _app(
        EntityList<_Row>(
          title: 'Things',
          loadQuery: f.load,
          columns: [EntityColumn<_Row>('Name', (r) => r.name)],
          filterDefs: _filters,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Filters'));
    await t.pumpAndSettle();
    expect(find.text('Group by'), findsNothing);
    expect(find.text('Draft 0'), findsOneWidget);
  });

  testWidgets('menu offers None and the groupings; chip removes grouping', (
    t,
  ) async {
    final f = await _pump(t);
    await _menu(t);
    expect(find.text('Group by'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    await t.tap(find.text('Status').last);
    await t.pumpAndSettle();
    expect(f.groupCalls.last.$2, 'status');
    await _closeMenu(t);
    expect(find.text('Group: Status'), findsOneWidget);
    expect(find.byTooltip('Remove grouping Status'), findsOneWidget);
    // Rows are replaced by headers.
    expect(find.text('Draft 0'), findsNothing);
    expect(find.text('Draft'), findsOneWidget);

    await t.tap(find.byTooltip('Remove grouping Status'));
    await t.pumpAndSettle();
    expect(find.text('Group: Status'), findsNothing);
    expect(find.text('Draft 0'), findsOneWidget);
  });

  testWidgets('None in the menu ungroups', (t) async {
    await _pump(t);
    await _groupBy(t, 'Status');
    await t.tap(find.text('None'));
    await t.pumpAndSettle();
    await _closeMenu(t);
    expect(find.text('Group: Status'), findsNothing);
    expect(find.text('Draft 0'), findsOneWidget);
  });

  testWidgets('groups start collapsed with option labels and counts', (
    t,
  ) async {
    final f = await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('odd'), findsOneWidget); // raw value, no option
    expect(find.text('60'), findsOneWidget);
    expect(find.text('Sent 0'), findsNothing);
    // Only the first load of the plain list happened; no row load for groups.
    expect(f.queries.length, 1);
  });

  testWidgets('expanding loads rows with the group value merged', (t) async {
    final f = await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
    expect(find.text('Sent 1'), findsOneWidget);
    final q = f.queries.last;
    expect(_f(q, 'status'), {'sent'});
    expect(q.offset, 0);
    // Collapse hides the rows again; expanding again does not reload.
    final n = f.queries.length;
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsNothing);
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
    expect(f.queries.length, n);
  });

  testWidgets('a group value overrides an existing filter of that key', (
    t,
  ) async {
    final f = await _pump(t);
    await _menu(t);
    await t.tap(find.text('Draft').last);
    await t.tap(find.text('Sent').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Status').last);
    await t.pumpAndSettle();
    await _closeMenu(t);
    expect(f.groupCalls.last.$1.filters['status'], {'draft', 'sent'});
    await t.tap(find.text('Sent').last);
    await t.pumpAndSettle();
    expect(_f(f.queries.last, 'status'), {'sent'});
  });

  testWidgets('per-group load more appends with its own offset', (t) async {
    final f = await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    await t.tap(find.text('Draft'));
    await t.pumpAndSettle();
    expect(f.queries.last.limit, 50);
    await t.scrollUntilVisible(
      find.text('Load more'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Load more'));
    await t.pumpAndSettle();
    expect(f.queries.last.offset, 50);
    expect(_f(f.queries.last, 'status'), {'draft'});
    await t.scrollUntilVisible(
      find.text('Draft 59'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('group error shows retry that reloads only that group', (
    t,
  ) async {
    final f = await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    f.failNext = StateError('boom');
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Sent 0'), findsNothing);
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('group shows its own loading indicator', (t) async {
    final f = await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    f.gate = Completer<void>();
    await t.tap(find.text('Sent'));
    await t.pump();
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    f.gate!.complete();
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
  });

  testWidgets('search, filter and grouping changes reload and collapse', (
    t,
  ) async {
    final f = await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);

    final before = f.groupCalls.length;
    await t.enterText(find.byType(TextField), 'Sent');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    expect(f.groupCalls.length, before + 1);
    expect(f.groupCalls.last.$1.search, 'Sent');
    expect(find.text('Sent 0'), findsNothing);
    expect(find.text('Sent'), findsWidgets);

    await t.tap(find.text('Sent').last);
    await t.pumpAndSettle();
    expect(f.queries.last.search, 'Sent');

    await _menu(t);
    await t.tap(find.text('Germany'));
    await t.pumpAndSettle();
    await _closeMenu(t);
    expect(f.groupCalls.last.$1.filters['country'], {'de'});
    expect(find.text('Sent 1'), findsNothing);

    await t.tap(find.text('Sent').last);
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
    await _groupBy(t, 'Country');
    await _closeMenu(t);
    expect(f.groupCalls.last.$2, 'country');
    expect(find.text('Sent 0'), findsNothing);
    expect(find.text('Germany'), findsWidgets);
  });

  testWidgets('a stale groups response is ignored', (t) async {
    t.view.physicalSize = const Size(1200, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final slow = Completer<List<GroupBucket>>();
    var calls = 0;
    await t.pumpWidget(
      _app(
        EntityList<_Row>(
          title: 'Things',
          loadQuery: (q) async => (<_Row>[], 0),
          columns: [EntityColumn<_Row>('Name', (r) => r.name)],
          filterDefs: _filters,
          groupDefs: _groups,
          loadGroups: (q, by) {
            calls++;
            if (calls == 1) return slow.future;
            return Future.value([const GroupBucket('won', 7)]);
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Filters'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(RadioMenuButton<String?>, 'Status'));
    await t.pump(const Duration(milliseconds: 50));
    expect(calls, 1);
    await t.tap(find.text('Won'));
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.text('7'), findsOneWidget);
    slow.complete([const GroupBucket('draft', 99)]);
    await t.pumpAndSettle();
    expect(find.text('99'), findsNothing);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('selection works across groups by identity', (t) async {
    var sel = <_Row>[];
    await _pump(t, selectable: true, onSelection: (s) => sel = s);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    await t.tap(find.text('odd'));
    await t.pumpAndSettle();
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    final boxes = find.byType(Checkbox);
    expect(boxes, findsNWidgets(4)); // select all, Odd 0, Sent 0, Sent 1
    await t.tap(boxes.at(1));
    await t.pumpAndSettle();
    await t.tap(boxes.at(3));
    await t.pumpAndSettle();
    expect(sel.map((r) => r.name), ['Odd 0', 'Sent 1']);
    // Collapsing keeps the selection; the row is still checked when expanded again.
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(sel.length, 2);
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(t.widget<Checkbox>(find.byType(Checkbox).at(3)).value, true);
    // Select all covers the loaded rows of every expanded group.
    await t.tap(find.byType(Checkbox).first);
    await t.pumpAndSettle();
    expect(sel.length, 3);
    // A new grouping clears the selection.
    await _groupBy(t, 'Country');
    await _closeMenu(t);
    expect(sel, isEmpty);
  });

  testWidgets('headers are focusable, Enter and Space toggle', (t) async {
    await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    final header = find.ancestor(
      of: find.text('Sent'),
      matching: find.byType(InkWell),
    );
    final node = t.widget<InkWell>(header.first).focusNode!;
    node.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsNothing);
  });

  testWidgets('arrow keys move between headers and visible rows', (t) async {
    await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    InkWell ink(String text) => t.widget<InkWell>(
      find.ancestor(of: find.text(text), matching: find.byType(InkWell)).first,
    );
    ink('Draft').focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    // Draft is collapsed: the next focus target is the header "odd", then "Sent" and its rows.
    expect(ink('odd').focusNode!.hasFocus, true);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(ink('Sent').focusNode!.hasFocus, true);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pump();
    expect(ink('Sent 0').focusNode!.hasFocus, true);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.pump();
    expect(ink('Sent').focusNode!.hasFocus, true);
  });

  testWidgets('header semantics say label, count and state', (t) async {
    final handle = t.ensureSemantics();
    await _pump(t);
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    expect(find.bySemanticsLabel('Sent, 2 rows, collapsed'), findsOneWidget);
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.bySemanticsLabel('Sent, 2 rows, expanded'), findsOneWidget);
    expect(
      t.getSemantics(find.bySemanticsLabel('Sent, 2 rows, expanded')),
      isSemantics(
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasExpandedState: true,
        isExpanded: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('narrow layout: header tiles are at least 48 px', (t) async {
    await _pump(t, size: const Size(400, 800));
    await _groupBy(t, 'Status');
    await _closeMenu(t);
    final h = t.getSize(
      find
          .ancestor(of: find.text('Sent'), matching: find.byType(InkWell))
          .first,
    );
    expect(h.height, greaterThanOrEqualTo(48));
    await t.tap(find.text('Sent'));
    await t.pumpAndSettle();
    expect(find.text('Sent 0'), findsOneWidget);
  });

  group('favourites', () {
    testWidgets('save stores the grouping, apply restores it', (t) async {
      final store = MemoryKvStore();
      await _pump(t, prefsKey: 'things', store: store);
      await _groupBy(t, 'Status');
      await t.tap(find.text('Save current view as favourite'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'By status');
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(
        store.data['entity_list_fav:things'],
        contains('"groupBy":"status"'),
      );
      await _closeMenu(t);

      await t.pumpWidget(const SizedBox());
      final f = await _pump(t, prefsKey: 'things', store: store);
      expect(find.text('Group: Status'), findsNothing);
      await _menu(t);
      await t.tap(find.text('By status'));
      await t.pumpAndSettle();
      expect(f.groupCalls.last.$2, 'status');
      expect(find.text('Group: Status'), findsOneWidget);
    });

    testWidgets('a stored unknown grouping is dropped on apply', (t) async {
      final store = MemoryKvStore();
      store.data['entity_list_fav:things'] =
          '{"favourites":[{"name":"Odd","groupBy":"nope"}]}';
      final f = await _pump(t, prefsKey: 'things', store: store);
      await _menu(t);
      await t.tap(find.text('Odd'));
      await t.pumpAndSettle();
      expect(f.groupCalls, isEmpty);
      expect(find.textContaining('Group:'), findsNothing);
    });
  });

  testWidgets('asserts: groupDefs and loadGroups together', (t) async {
    final f = _Fake();
    await t.pumpWidget(
      _app(
        EntityList<_Row>(
          title: 't',
          loadQuery: f.load,
          columns: [EntityColumn<_Row>('Name', (r) => r.name)],
          filterDefs: _filters,
          groupDefs: _groups,
        ),
      ),
    );
    expect(t.takeException(), isA<AssertionError>());
  });

  testWidgets('asserts: every group key needs a filter', (t) async {
    final f = _Fake();
    await t.pumpWidget(
      _app(
        EntityList<_Row>(
          title: 't',
          loadQuery: f.load,
          columns: [EntityColumn<_Row>('Name', (r) => r.name)],
          filterDefs: const [],
          groupDefs: _groups,
          loadGroups: f.loadGroups,
        ),
      ),
    );
    expect(t.takeException(), isA<AssertionError>());
  });
}
