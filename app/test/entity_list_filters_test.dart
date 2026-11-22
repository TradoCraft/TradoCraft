import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/framework/data/repository.dart';
import 'package:tradocraft_app/framework/search/filter_model.dart';
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

const _defs = [
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

class _SilentStore implements KvStore {
  @override
  Future<String?> get(String key) => Completer<String?>().future;
  @override
  Future<void> set(String key, String value) async {}
  @override
  Future<void> remove(String key) async {}
}

/// A store whose reads fail or wait for a gate and whose writes can fail.
class _ScriptedStore implements KvStore {
  final data = <String, String>{};
  final sets = <String>[];
  bool failGets = false;
  bool failSets = false;
  Completer<String?>? gate;
  @override
  Future<String?> get(String key) {
    if (failGets) return Future.error(StateError('read failed'));
    return gate?.future ?? Future.value(data[key]);
  }

  @override
  Future<void> set(String key, String value) async {
    sets.add(key);
    if (failSets) throw StateError('write failed');
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
}

const _oldFav =
    '{"favourites":[{"name":"Old","search":"x","filters":{"status":["draft"]}}]}';

class _Loader {
  _Loader([int n = 60]) : all = List.generate(n, (i) => 'Item $i');
  final List<String> all;
  final queries = <ListQuery>[];
  Future<(List<String>, int)> call(ListQuery q) async {
    queries.add(q);
    final hits = all.where((s) => q.search == null || s.contains(q.search!));
    return (hits.skip(q.offset).take(q.limit).toList(), hits.length);
  }
}

List<EntityColumn<String>> _cols() => [EntityColumn('Name', (s) => s)];

Future<_Loader> _pump(
  WidgetTester t, {
  Size? size,
  String? prefsKey,
  KvStore? store,
  List<FilterDef> defs = _defs,
  void Function(List<String>)? onSelection,
  bool selectable = false,
}) async {
  _size(t, size ?? const Size(1200, 800));
  final l = _Loader();
  await t.pumpWidget(
    _app(
      EntityList<String>(
        title: 'Things',
        loadQuery: l.call,
        columns: _cols(),
        filterDefs: defs,
        prefsKey: prefsKey,
        prefsStore: store,
        selectable: selectable,
        idOf: selectable ? (s) => s : null,
        onSelectionChanged: onSelection,
      ),
    ),
  );
  await t.pumpAndSettle();
  return l;
}

Future<void> _openMenu(WidgetTester t) async {
  if (find.text('Clear filters').evaluate().isNotEmpty) return;
  await t.tap(find.byTooltip('Filters'));
  await t.pumpAndSettle();
}

Future<void> _pick(WidgetTester t, String option) async {
  await t.tap(find.text(option));
  await t.pumpAndSettle();
}

Set<String>? _f(_Loader l, String key) =>
    l.queries.last.filters[key] as Set<String>?;

void main() {
  testWidgets('without filterDefs nothing changes', (t) async {
    final l = await _pump(t, defs: const []);
    expect(find.byTooltip('Filters'), findsNothing);
    expect(find.byType(InputChip), findsNothing);
    expect(l.queries.last.filters, isEmpty);
    expect(l.queries.length, 1);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('picking options reloads from offset 0 and shows chips', (
    t,
  ) async {
    final l = await _pump(t);
    await t.scrollUntilVisible(
      find.text('Load more'),
      500,
      scrollable: find.byType(Scrollable).last,
    );
    await t.tap(find.text('Load more'));
    await t.pumpAndSettle();
    expect(l.queries.last.offset, 50);

    await _openMenu(t);
    // All options start ticked; unticking Draft leaves Sent and Won selected.
    await _pick(t, 'Draft');
    expect(_f(l, 'status'), {'sent', 'won'});
    expect(l.queries.last.offset, 0);
    expect(find.text('Status: Sent or Won'), findsOneWidget);
    // Unchecking Sent leaves Won; unchecking Germany leaves Netherlands.
    await _pick(t, 'Sent');
    await _pick(t, 'Germany');
    expect(_f(l, 'status'), {'won'});
    expect(_f(l, 'country'), {'nl'});
    expect(find.text('Status: Won'), findsOneWidget);
    expect(find.text('Country: Netherlands'), findsOneWidget);
    // Re-checking Sent restores both Sent and Won.
    await _pick(t, 'Sent');
    expect(_f(l, 'status'), {'sent', 'won'});
  });

  testWidgets('chips remove one filter, Clear filters resets all to ticked', (t) async {
    final l = await _pump(t);
    await _openMenu(t);
    await _pick(t, 'Draft');
    await _pick(t, 'Germany');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove filter Status'));
    await t.pumpAndSettle();
    expect(l.queries.last.filters.keys, ['country']);
    expect(find.text('Status: Sent or Won'), findsNothing);

    await _openMenu(t);
    await _pick(t, 'Clear filters');
    expect(l.queries.last.filters, isEmpty);
    expect(find.byType(InputChip), findsNothing);
  });

  testWidgets('tapping the chip itself removes it too', (t) async {
    final l = await _pump(t);
    await _openMenu(t);
    await _pick(t, 'Draft');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(find.text('Status: Sent or Won'));
    await t.pumpAndSettle();
    expect(l.queries.last.filters, isEmpty);
  });

  testWidgets('backspace in an empty search removes the last chip', (t) async {
    final l = await _pump(t);
    await _openMenu(t);
    await _pick(t, 'Draft');
    await _pick(t, 'Germany');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();
    expect(l.queries.last.filters.keys, ['status']);
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();
    expect(l.queries.last.filters, isEmpty);

    // With text in the field, backspace edits the text and keeps the chips.
    await _openMenu(t);
    await _pick(t, 'Draft');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'ab');
    await t.sendKeyEvent(LogicalKeyboardKey.backspace);
    await t.pumpAndSettle();
    expect(find.text('Status: Sent or Won'), findsOneWidget);
  });

  testWidgets('Select all / Deselect all toggles all options', (t) async {
    final l = await _pump(t);
    await _openMenu(t);
    // Starts with all ticked -> button says Deselect all.
    expect(find.text('Deselect all'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('filter-toggle-all')));
    await t.pumpAndSettle();
    expect(find.text('Select all'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('filter-toggle-all')));
    await t.pumpAndSettle();
    expect(find.text('Deselect all'), findsOneWidget);
    expect(l.queries.last.filters, isEmpty);
  });

  testWidgets('a filter change clears the row selection', (t) async {
    final seen = <List<String>>[];
    await _pump(t, selectable: true, onSelection: seen.add);
    await t.tap(find.byType(Checkbox).at(1));
    await t.pumpAndSettle();
    expect(seen.last, isNotEmpty);
    await _openMenu(t);
    await _pick(t, 'Draft');
    expect(seen.last, isEmpty);
  });

  testWidgets('a stale response is ignored after a filter change', (t) async {
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
          filterDefs: _defs,
        ),
      ),
    );
    await t.pump();
    await t.tap(find.byTooltip('Filters'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Draft'));
    await t.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    first.complete((['Old'], 1));
    await t.pumpAndSettle();
    expect(find.text('Old'), findsNothing);
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('narrow layout: 48 px targets and semantics', (t) async {
    final handle = t.ensureSemantics();
    final l = await _pump(t, size: const Size(390, 800));
    expect(
      t.getSize(find.byTooltip('Filters')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      t.getSize(find.byTooltip('Filters')).width,
      greaterThanOrEqualTo(48),
    );
    await _openMenu(t);
    for (final label in ['Draft', 'Germany', 'Clear filters']) {
      final item = find.ancestor(
        of: find.text(label),
        matching: find.byType(MenuItemButton).evaluate().isEmpty
            ? find.byType(CheckboxMenuButton)
            : find.byType(ConstrainedBox),
      );
      expect(item, findsWidgets);
    }
    expect(
      t.getSize(find.widgetWithText(CheckboxMenuButton, 'Draft')).height,
      greaterThanOrEqualTo(48),
    );
    expect(
      t.getSize(find.widgetWithText(MenuItemButton, 'Clear filters')).height,
      greaterThanOrEqualTo(48),
    );
    await _pick(t, 'Draft');
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(InputChip)).height, greaterThanOrEqualTo(48));
    expect(find.byTooltip('Remove filter Status'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Status: Sent or Won')), findsWidgets);
    expect(l.queries.last.filters, isNotEmpty);
    handle.dispose();
  });

  group('favourites', () {
    Future<void> save(WidgetTester t, String name) async {
      await _openMenu(t);
      await t.tap(find.text('Save current view as favourite'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, name);
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
    }

    testWidgets('hidden without prefsKey', (t) async {
      await _pump(t);
      await _openMenu(t);
      expect(find.text('Favourites'), findsNothing);
      expect(find.text('Save current view as favourite'), findsNothing);
    });

    testWidgets('save, apply on a new list, delete', (t) async {
      final store = MemoryKvStore();
      await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      expect(find.text('No favourites yet'), findsOneWidget);
      await _pick(t, 'Draft');
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'Item 1');
      await t.pump();
      await save(t, 'My drafts');
      expect(store.data.keys, contains('entity_list_fav:things'));
      expect(store.data['entity_list_fav:things'], contains('My drafts'));
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();

      // A fresh list: the favourite is there and applies search and filters.
      await t.pumpWidget(const SizedBox());
      final l = await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      await t.tap(find.text('My drafts'));
      await t.pumpAndSettle();
      expect(l.queries.last.search, 'Item 1');
      expect(_f(l, 'status'), {'sent', 'won'});
      expect(find.text('Status: Sent or Won'), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'Item 1',
      );

      await _openMenu(t);
      await t.tap(find.byTooltip('Delete favourite My drafts'));
      await t.pumpAndSettle();
      expect(
        store.data['entity_list_fav:things'],
        isNot(contains('My drafts')),
      );
      await _openMenu(t);
      expect(find.text('My drafts'), findsNothing);
    });

    testWidgets('unknown filters and options are dropped on apply', (t) async {
      final store = MemoryKvStore()
        ..data['entity_list_fav:things'] =
            '{"favourites":[{"name":"Old","search":"x","future":1,'
            '"filters":{"status":["draft","gone"],"nope":["a"]}}]}';
      final l = await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      await t.tap(find.text('Old'));
      await t.pumpAndSettle();
      expect(l.queries.last.filters.keys, ['status']);
      expect(_f(l, 'status'), {'draft'});
      expect(l.queries.last.search, 'x');
    });

    testWidgets('a damaged value is ignored', (t) async {
      final store = MemoryKvStore()..data['entity_list_fav:things'] = '{oops';
      final l = await _pump(t, prefsKey: 'things', store: store);
      expect(l.queries, isNotEmpty);
      await _openMenu(t);
      expect(find.text('No favourites yet'), findsOneWidget);
    });

    bool saveEnabled(WidgetTester t) =>
        t
            .widget<MenuItemButton>(
              find.widgetWithText(
                MenuItemButton,
                'Save current view as favourite',
              ),
            )
            .onPressed !=
        null;

    testWidgets('the accessibility tap action applies a favourite', (t) async {
      final handle = t.ensureSemantics();
      final store = MemoryKvStore()..data['entity_list_fav:things'] = _oldFav;
      final l = await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      await t.pumpAndSettle();
      t.semantics.tap(find.semantics.byLabel('Apply favourite Old'));
      await t.pumpAndSettle();
      expect(l.queries.last.search, 'x');
      expect(_f(l, 'status'), {'draft'});
      handle.dispose();
    });

    testWidgets('a failed write restores the list and tells the user', (
      t,
    ) async {
      final store = _ScriptedStore()..data['entity_list_fav:things'] = _oldFav;
      await _pump(t, prefsKey: 'things', store: store);
      store.failSets = true;
      await save(t, 'New one');
      expect(find.byType(SnackBar), findsOneWidget);
      await _openMenu(t);
      expect(find.text('Old'), findsOneWidget);
      expect(find.text('New one'), findsNothing);
    });

    testWidgets('a failed read blocks writes until retry succeeds', (t) async {
      final store = _ScriptedStore()
        ..data['entity_list_fav:things'] = _oldFav
        ..failGets = true;
      await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      expect(find.text('Retry'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      expect(find.text('Old'), findsNothing);

      store
        ..failGets = false
        ..gate = Completer<String?>();
      await t.tap(find.text('Retry')); // closes the menu
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byTooltip('Filters'));
      await t.pump(const Duration(milliseconds: 300));
      expect(saveEnabled(t), isFalse); // still pending
      expect(find.text('Retry'), findsNothing);
      store.gate!.complete(_oldFav);
      await t.pumpAndSettle();
      expect(saveEnabled(t), isTrue);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Old'), findsOneWidget);

      await save(t, 'New one');
      expect(store.data['entity_list_fav:things'], contains('Old'));
      expect(store.data['entity_list_fav:things'], contains('New one'));
      expect(store.sets.where((k) => k.contains('fav')), hasLength(1));
    });

    testWidgets('a read that times out offers retry and saves nothing', (
      t,
    ) async {
      final store = _ScriptedStore()..gate = Completer<String?>();
      await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      expect(find.text('Retry'), findsOneWidget);
      expect(saveEnabled(t), isFalse);
      expect(store.sets, isEmpty);
    });

    testWidgets('an empty store is ready', (t) async {
      final store = _ScriptedStore();
      await _pump(t, prefsKey: 'things', store: store);
      await _openMenu(t);
      expect(find.text('Retry'), findsNothing);
      expect(saveEnabled(t), isTrue);
    });

    testWidgets('a store that never answers does not block the list', (
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
            filterDefs: _defs,
            prefsKey: 'things',
            prefsStore: _SilentStore(),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 2100));
      await t.pumpAndSettle();
      expect(l.queries, hasLength(1));
      expect(find.text('Item 0'), findsOneWidget);
    });
  });
}
