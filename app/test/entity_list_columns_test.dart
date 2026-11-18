import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/framework/data/repository.dart';
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

void _size(WidgetTester t, [Size s = const Size(1200, 800)]) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

List<String> _data([int n = 60]) =>
    List.generate(n, (i) => 'Item ${i.toString().padLeft(2, '0')}');

/// A store whose reads never complete (an unavailable platform store).
class _SilentStore implements KvStore {
  @override
  Future<String?> get(String key) => Completer<String?>().future;
  @override
  Future<void> set(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
}

/// A loader that records every query it gets.
class _Loader {
  _Loader([int n = 60]) : all = _data(n);
  final List<String> all;
  final queries = <ListQuery>[];
  Future<(List<String>, int)> call(ListQuery q) async {
    queries.add(q);
    final hits = all.where((s) => q.search == null || s.contains(q.search!));
    return (hits.skip(q.offset).take(q.limit).toList(), hits.length);
  }
}

List<EntityColumn<String>> _cols() => [
  EntityColumn('Name', (s) => s, sortKey: 'name'),
  EntityColumn('Len', (s) => '${s.length}', sortKey: 'len', numeric: true),
];

Finder _handles() =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ResizeHandle');

void main() {
  group('sorting', () {
    testWidgets('cycles none, asc, desc, none and resets paging', (t) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(l.queries.last.sort, isNull);

      await t.scrollUntilVisible(
        find.text('Load more'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Load more'));
      await t.pumpAndSettle();
      expect(l.queries.last.offset, 50);

      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(l.queries.last.sort, 'name');
      expect(l.queries.last.offset, 0);
      expect(find.text('50 of 60'), findsOneWidget);
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(l.queries.last.sort, '-name');
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(l.queries.last.sort, isNull);
    });

    testWidgets('shift adds a secondary key, at most three', (t) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: [
              ..._cols(),
              EntityColumn('Third', (s) => s, sortKey: 'third'),
              EntityColumn('Fourth', (s) => s, sortKey: 'fourth'),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.tap(find.text('Len'));
      await t.pumpAndSettle();
      expect(l.queries.last.sort, 'name,len');
      await t.tap(find.text('Len'));
      await t.pumpAndSettle();
      expect(l.queries.last.sort, 'name,-len');
      await t.tap(find.text('Third'));
      await t.pumpAndSettle();
      expect(l.queries.last.sort, 'name,-len,third');
      final n = l.queries.length;
      await t.tap(find.text('Fourth'));
      await t.pumpAndSettle();
      expect(l.queries.length, n);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('keyboard toggles and the header says its state', (t) async {
      _size(t);
      final handle = t.ensureSemantics();
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Name, not sorted'), findsOneWidget);
      // Tab from the search field to the first sortable header, then Enter.
      await t.tap(find.byType(TextField));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(l.queries.last.sort, 'name');
      expect(find.bySemanticsLabel('Name, sorted ascending'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pumpAndSettle();
      expect(l.queries.last.sort, '-name');
      expect(find.bySemanticsLabel('Name, sorted descending'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a stale response is ignored after a sort change', (t) async {
      _size(t);
      final first = Completer<(List<String>, int)>();
      var calls = 0;
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: (q) =>
                ++calls == 1 ? first.future : Future.value((['New'], 1)),
            columns: _cols(),
          ),
        ),
      );
      await t.pump();
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(find.text('New'), findsOneWidget);
      first.complete((['Old'], 1));
      await t.pumpAndSettle();
      expect(find.text('Old'), findsNothing);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('exactly one of load and loadQuery', (t) async {
      expect(
        () => EntityList<String>(title: 'x', columns: _cols()),
        throwsAssertionError,
      );
      expect(
        () => EntityList<String>(
          title: 'x',
          columns: _cols(),
          load: (q, o, l) async => (<String>[], 0),
          loadQuery: (q) async => (<String>[], 0),
        ),
        throwsAssertionError,
      );
      expect(
        () => EntityList<String>(
          title: 'x',
          columns: _cols(),
          loadQuery: (q) async => (<String>[], 0),
          selectable: true,
        ),
        throwsAssertionError,
      );
    });
  });

  group('columns', () {
    testWidgets('resize by drag, double-click resets', (t) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
            resizableColumns: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      final x0 = t.getCenter(_handles().first).dx;
      await t.drag(_handles().first, const Offset(50, 0));
      await t.pumpAndSettle();
      // The drag slop is not delivered to the handle, so it moves by less than the gesture.
      expect(t.getCenter(_handles().first).dx, greaterThan(x0 + 20));

      final h = _handles().first;
      await t.tap(h);
      await t.pump(const Duration(milliseconds: 50));
      await t.tap(h);
      await t.pumpAndSettle();
      expect(t.getCenter(_handles().first).dx, closeTo(x0, 1));
    });

    testWidgets('never narrower than the minimum, scrolls when too wide', (
      t,
    ) async {
      _size(t, const Size(800, 800));
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
            resizableColumns: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.drag(_handles().first, const Offset(-2000, 0));
      await t.pumpAndSettle();
      final a = t.getCenter(_handles().first).dx;
      final b = t.getCenter(_handles().last).dx;
      expect(b - a, greaterThanOrEqualTo(64));
      await t.drag(_handles().first, const Offset(1500, 0));
      await t.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
      );
    });

    testWidgets('visibility toggle keeps one column visible', (t) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
            columnMenu: true,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Columns'));
      await t.pumpAndSettle();
      await t.tap(find.text('Len').last);
      await t.pumpAndSettle();
      expect(find.text('Len'), findsNothing);

      await t.tap(find.byTooltip('Columns'));
      await t.pumpAndSettle();
      await t.tap(find.text('Name').last);
      await t.pumpAndSettle();
      // Still there: the last visible column cannot be hidden.
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Item 00'), findsOneWidget);

      await t.tap(find.byTooltip('Columns'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reset layout'));
      await t.pumpAndSettle();
      expect(find.text('Len'), findsOneWidget);
    });

    testWidgets('defaultVisible false starts hidden', (t) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columnMenu: true,
            columns: [
              EntityColumn('Name', (s) => s),
              EntityColumn('Extra', (s) => 'x', defaultVisible: false),
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Extra'), findsNothing);
    });

    testWidgets('layout and sort persist per prefsKey', (t) async {
      _size(t);
      final store = MemoryKvStore();
      Widget build(_Loader l) => _app(
        EntityList<String>(
          key: UniqueKey(),
          title: 'Things',
          loadQuery: l.call,
          columns: _cols(),
          columnMenu: true,
          resizableColumns: true,
          prefsKey: 'things',
          prefsStore: store,
        ),
      );
      final l1 = _Loader();
      await t.pumpWidget(build(l1));
      await t.pumpAndSettle();
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Columns'));
      await t.pumpAndSettle();
      await t.tap(find.text('Len').last);
      await t.pumpAndSettle();
      await t.drag(_handles().first, const Offset(40, 0));
      await t.pumpAndSettle();
      expect(store.data.keys, contains('entity_list:things'));

      final l2 = _Loader();
      await t.pumpWidget(build(l2));
      await t.pumpAndSettle();
      expect(l2.queries.first.sort, 'name');
      expect(find.text('Len'), findsNothing);
      expect(find.text('Name'), findsOneWidget);
    });

    testWidgets('without prefsKey nothing is stored', (t) async {
      _size(t);
      final store = MemoryKvStore();
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
            prefsStore: store,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(store.data, isEmpty);
    });

    testWidgets('a damaged stored layout falls back to the default', (t) async {
      _size(t);
      final store = MemoryKvStore()..data['entity_list:things'] = '{not json';
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
            prefsKey: 'things',
            prefsStore: store,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Item 00'), findsOneWidget);
      expect(l.queries.first.sort, isNull);
    });

    testWidgets('a store that never answers does not hold the list back', (
      t,
    ) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            loadQuery: l.call,
            columns: _cols(),
            prefsKey: 'things',
            prefsStore: _SilentStore(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Item 00'), findsOneWidget);
      expect(l.queries.first.sort, isNull);
    });
  });

  group('selection', () {
    Widget list(
      _Loader l, {
      List<BulkAction<String>> bulk = const [],
      void Function(List<String>)? onSel,
      Future<bool?> Function(String)? onOpen,
    }) => _app(
      EntityList<String>(
        title: 'Things',
        loadQuery: l.call,
        columns: _cols(),
        selectable: true,
        idOf: (s) => s,
        bulkActions: bulk,
        onSelectionChanged: onSel,
        onOpen: onOpen,
      ),
    );

    testWidgets('select all, range, and the bar replaces the count', (t) async {
      _size(t);
      final l = _Loader();
      List<String> last = [];
      await t.pumpWidget(list(l, onSel: (s) => last = s));
      await t.pumpAndSettle();
      expect(find.text('50 of 60'), findsOneWidget);

      await t.tap(find.byType(Checkbox).at(1));
      await t.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('50 of 60'), findsNothing);
      expect(last, ['Item 00']);

      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.tap(find.byType(Checkbox).at(4));
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(last, ['Item 00', 'Item 01', 'Item 02', 'Item 03']);

      await t.tap(find.byType(Checkbox).first);
      await t.pump();
      expect(find.text('50 selected'), findsOneWidget);
      await t.tap(find.byType(Checkbox).first);
      await t.pump();
      expect(find.text('50 of 60'), findsOneWidget);
      expect(last, isEmpty);
    });

    testWidgets('survives load more, cleared on a sort or search change', (
      t,
    ) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(list(l));
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox).at(1));
      await t.pump();
      await t.scrollUntilVisible(
        find.text('Load more'),
        500,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Load more'));
      await t.pumpAndSettle();
      expect(find.text('1 selected'), findsOneWidget);

      await t.scrollUntilVisible(
        find.text('Name'),
        -500,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('Name'));
      await t.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);

      await t.tap(find.byType(Checkbox).at(1));
      await t.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await t.enterText(find.byType(TextField), 'Item 1');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('tapping a checkbox does not open the row', (t) async {
      _size(t);
      final l = _Loader();
      final opened = <String>[];
      await t.pumpWidget(
        list(
          l,
          onOpen: (s) async {
            opened.add(s);
            return false;
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox).at(1));
      await t.pump();
      expect(opened, isEmpty);
      await t.tap(find.text('Item 02'));
      await t.pump();
      expect(opened, ['Item 02']);
    });

    testWidgets('bulk action asks, runs on the items, reloads, clears', (
      t,
    ) async {
      _size(t);
      final l = _Loader();
      final ran = <List<String>>[];
      await t.pumpWidget(
        list(
          l,
          bulk: [
            BulkAction<String>(
              label: 'Archive',
              icon: Icons.archive,
              confirm: 'Archive these?',
              run: (items) async => ran.add(items),
            ),
            BulkAction<String>(
              label: 'Never',
              icon: Icons.block,
              enabled: (_) => false,
              run: (_) async {},
            ),
          ],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox).at(1));
      await t.tap(find.byType(Checkbox).at(2));
      await t.pump();
      expect(
        t
            .widget<TextButton>(find.widgetWithText(TextButton, 'Never'))
            .onPressed,
        isNull,
      );
      final calls = l.queries.length;

      await t.tap(find.text('Archive'));
      await t.pumpAndSettle();
      expect(find.text('Archive these?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(ran, isEmpty);
      expect(find.text('2 selected'), findsOneWidget);

      await t.tap(find.text('Archive'));
      await t.pumpAndSettle();
      await t.tap(find.text('Confirm'));
      await t.pumpAndSettle();
      expect(ran.single, ['Item 00', 'Item 01']);
      expect(l.queries.length, calls + 1);
      expect(find.textContaining('selected'), findsNothing);
    });

    testWidgets('a failing bulk action shows the error and keeps selection', (
      t,
    ) async {
      _size(t);
      final l = _Loader();
      await t.pumpWidget(
        list(
          l,
          bulk: [
            BulkAction<String>(
              label: 'Boom',
              icon: Icons.warning,
              run: (_) async => throw StateError('nope'),
            ),
          ],
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(Checkbox).at(1));
      await t.pump();
      await t.tap(find.text('Boom'));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('arrow keys and Space still work with checkboxes', (t) async {
      _size(t);
      final l = _Loader();
      final opened = <String>[];
      await t.pumpWidget(
        list(
          l,
          onOpen: (s) async {
            opened.add(s);
            return false;
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(TextField));
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await t.sendKeyEvent(LogicalKeyboardKey.space);
      await t.pump();
      expect(find.text('1 selected'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(opened, ['Item 01']);
    });

    testWidgets('narrow: long-press enters selection mode', (t) async {
      _size(t, const Size(400, 800));
      final l = _Loader();
      final opened = <String>[];
      await t.pumpWidget(
        list(
          l,
          onOpen: (s) async {
            opened.add(s);
            return false;
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(Checkbox), findsNothing);
      await t.longPress(find.byType(ListTile).first);
      await t.pump();
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.byType(Checkbox), findsWidgets);
      await t.tap(find.byType(ListTile).at(1));
      await t.pump();
      expect(find.text('2 selected'), findsOneWidget);
      expect(opened, isEmpty);
      await t.tap(find.byTooltip('Clear selection'));
      await t.pump();
      expect(find.byType(Checkbox), findsNothing);
      await t.tap(find.byType(ListTile).first);
      expect(opened, hasLength(1));
    });
  });

  testWidgets('a plain list renders as before', (t) async {
    _size(t);
    await t.pumpWidget(
      _app(
        EntityList<String>(
          title: 'Things',
          load: (q, o, l) async => (_data(3), 3),
          columns: [
            EntityColumn('Name', (s) => s),
            EntityColumn('Len', (s) => '${s.length}'),
          ],
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.byIcon(Icons.tune), findsNothing);
    expect(_handles(), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    // Flex layout: the header cell and the row cell share the left edge.
    expect(
      t.getTopLeft(find.text('Name')).dx,
      t.getTopLeft(find.text('Item 00')).dx,
    );
  });
}
