import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/features/admin/company_logo_page.dart';
import 'package:tradocraft_app/features/price_lists/price_list_editor_page.dart';
import 'package:tradocraft_app/features/price_lists/price_list_generate.dart';
import 'package:tradocraft_app/features/price_lists/price_list_groups.dart';
import 'package:tradocraft_app/features/price_lists/price_lists_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';
import 'package:tradocraft_app/shared/file_export.dart';

import 'fake_http.dart';

Future<GoRouter> _pump(
  WidgetTester tester,
  FakeHttp http, {
  String start = '/price-lists',
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: start,
    routes: [
      GoRoute(
        path: '/price-lists',
        builder: (_, _) => const _Host(PriceListsPage()),
      ),
      GoRoute(
        path: '/price-lists/:id',
        builder: (_, s) => _Host(PriceListEditorPage(id: s.pathParameters['id']!)),
      ),
      GoRoute(path: '/admin', builder: (_, _) => const _Host(AdminPage())),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http)), ...overrides],
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
  return router;
}

class _Host extends ConsumerWidget {
  const _Host(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(meProvider);
    return Scaffold(body: child);
  }
}

Map<String, Object?> _list({
  String id = 'pl1',
  String code = 'PL-2027',
  String name = 'Retail 2027',
  List<Map<String, Object?>>? zones,
  int items = 2,
}) => {
  'id': id,
  'code': code,
  'name': name,
  'zones': zones ?? [_plZone('z1', 'Z1', 'Retail', ['nl', 'en'], 1)],
  'valid_from': '2027-01-01',
  'settings': {
    'footer_text': '',
    'currency_symbol': '',
    'accent_color': '#1f4e79',
    'show_unit': true,
    'show_logo': true,
  },
  'item_count': items,
};

Map<String, Object?> _plZone(
  String id,
  String code,
  String name,
  List<String> languages,
  int sort,
) => {
  'price_zone_id': id,
  'price_zone_code': code,
  'price_zone_name': name,
  'languages': languages,
  'sort_order': sort,
};

Map<String, Object?> _export(
  String id,
  String code,
  String name, {
  List<String> groups = const [],
  String? file,
}) => {
  'id': id,
  'code': code,
  'name': name,
  'sort_order': 10,
  'group_ids': groups,
  'file_name': ?file,
};

Map<String, Object?> _planEntry(
  String zone,
  String lang,
  String? exportId,
  String path, {
  String format = 'pdf',
}) => {
  'zone_id': 'z-$zone',
  'zone_code': zone,
  'lang': lang,
  'export_id': ?exportId,
  'format': format,
  'relative_path': path,
};

Map<String, Object?> _group(
  String id,
  String title, {
  String? parent,
  int sort = 10,
  bool pageBreak = false,
  bool showTitle = true,
  String gap = '0.00',
}) => {
  'id': id,
  'parent_id': parent,
  'sort_order': sort,
  'title': {'nl': title},
  'page_break': pageBreak,
  'show_title': showTitle,
  'gap_mm': gap,
};

Map<String, Object?> _item(
  String id,
  String code, {
  String group = 'g1',
  String key = '',
  bool hidden = false,
}) => {
  'id': id,
  'product_id': 'p-$code',
  'product_code': code,
  'product_name': 'Name $code',
  'group_id': group,
  'sort_key': key,
  'price_on_request': false,
  'net': false,
  'indicative': false,
  'hidden': hidden,
  'description': <String, String>{},
};

Map<String, Object?> _zone() => {
  'id': 'z1',
  'code': 'Z1',
  'name': 'Retail',
  'sort_order': 1,
};

void main() {
  testWidgets('lists price lists, validates and creates one, then opens the editor', (
    tester,
  ) async {
    final lists = [_list()];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['price_lists.read', 'price_lists.write']),
      'GET /api/v1/price-lists': (_) => lists,
      'GET /api/v1/price-zones': (_) => [_zone()],
      'POST /api/v1/price-lists': (b) {
        final m = b! as Map;
        lists.add(_list(id: 'pl2', code: m['code']! as String, name: 'New'));
        return lists.last;
      },
      'GET /api/v1/price-lists/pl2': (_) => lists.last,
      'GET /api/v1/price-lists/pl2/groups': (_) => [],
      'GET /api/v1/price-lists/pl2/items': (_) => [],
    });
    await _pump(tester, http);
    expect(find.text('PL-2027  Retail 2027'), findsOneWidget);
    expect(find.textContaining('Z1 NL EN'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pl-new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pl-save')));
    await tester.pumpAndSettle();
    expect(find.text('Code and name are required.'), findsOneWidget);
    expect(http.requests, isNot(contains('POST /api/v1/price-lists')));

    await tester.enterText(find.byKey(const ValueKey('pl-code')), 'PL-NEW');
    await tester.enterText(find.byKey(const ValueKey('pl-name')), 'New');
    // Zones and languages are no longer part of this dialog.
    expect(find.byKey(const ValueKey('pl-zone')), findsNothing);
    expect(find.byKey(const ValueKey('pl-lang-fr')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pl-show-logo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pl-save')));
    await tester.pumpAndSettle();
    final body = http.bodies['POST /api/v1/price-lists']! as Map;
    expect(body['code'], 'PL-NEW');
    expect(body.containsKey('price_zone_id'), isFalse);
    expect(body.containsKey('languages'), isFalse);
    expect((body['valid_from'] as String).substring(0, 10), isNotEmpty);
    expect((body['settings'] as Map)['show_logo'], false);
    // A new list opens in the editor.
    expect(find.byKey(const ValueKey('ple-generate')), findsOneWidget);
  });

  testWidgets('a reader sees the lists but no edit controls; delete asks first', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['price_lists.read']),
      'GET /api/v1/price-lists': (_) => [_list()],
    });
    await _pump(tester, http);
    expect(find.byKey(const ValueKey('pl-new')), findsNothing);
    expect(find.byKey(const ValueKey('pl-edit-PL-2027')), findsNothing);
    expect(find.byKey(const ValueKey('pl-open-PL-2027')), findsOneWidget);
  });

  testWidgets('deletes a list after confirmation', (tester) async {
    final lists = [_list()];
    final http = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['price_lists.read', 'price_lists.write']),
      'GET /api/v1/price-lists': (_) => lists,
      'DELETE /api/v1/price-lists/pl1': (_) {
        lists.clear();
        return null;
      },
    });
    await _pump(tester, http);
    await tester.tap(find.byKey(const ValueKey('pl-del-PL-2027')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pl-delete-confirm')));
    await tester.pumpAndSettle();
    expect(http.requests, contains('DELETE /api/v1/price-lists/pl1'));
    expect(find.text('No price lists yet.'), findsOneWidget);
  });

  group('group tree logic', () {
    PriceListGroup g(String id, String? parent, int sort) => PriceListGroup.fromJson(
      _group(id, id, parent: parent, sort: sort),
    );

    test('flattens depth-first in sort order and measures levels', () {
      final all = [g('b', null, 20), g('a', null, 10), g('a2', 'a', 10), g('a21', 'a2', 10)];
      expect(
        flattenGroups(all).map((n) => '${n.group.id}:${n.depth}').toList(),
        ['a:0', 'a2:1', 'a21:2', 'b:0'],
      );
      expect(levelOf(all, all[3]), 3);
      expect(subtreeHeight(all, all[1]), 3);
    });

    test('sort keys compare numerically per segment', () {
      expect(compareSortKeys('1.2', '1.10'), lessThan(0));
      expect(compareSortKeys('2', '1.9'), greaterThan(0));
      expect(compareSortKeys('', '1'), lessThan(0));
    });
  });

  group('editor', () {
    late List<Map<String, Object?>> groups;
    late List<Map<String, Object?>> items;
    late List<Map<String, Object?>> exports;
    late FakeHttp http;

    setUp(() {
      exports = [];
      groups = [
        _group('g1', 'Pumps', sort: 10, pageBreak: true),
        _group('g2', 'Valves', sort: 20),
        _group('g3', 'Spacer', sort: 30, showTitle: false, gap: '8.50'),
      ];
      items = [_item('i2', 'P-10', key: '1.10'), _item('i1', 'P-2', key: '1.2')];
      http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['price_lists.read', 'price_lists.write']),
        'GET /api/v1/price-lists/pl1': (_) => _list(),
        'GET /api/v1/price-lists/pl1/groups': (_) => groups,
        'GET /api/v1/price-lists/pl1/items': (_) => items,
        'PUT /api/v1/price-lists/pl1/groups/g1': (_) => groups[0],
        'PUT /api/v1/price-lists/pl1/groups/g2': (_) => groups[1],
        'PUT /api/v1/price-lists/pl1/groups/g3': (_) => groups[2],
        'POST /api/v1/price-lists/pl1/groups': (_) => groups[0],
        'POST /api/v1/price-lists/pl1/items': (_) => items[0],
        'PUT /api/v1/price-lists/pl1/items/i1': (_) => items[1],
        'DELETE /api/v1/price-lists/pl1/items/i1': (_) => null,
        'GET /api/v1/products': (_) => {
          'items': [
            {
              'id': 'p-NEW',
              'code': 'NEW-1',
              'name': 'Brand new',
              'description': '',
              'active': true,
              'product_type': 'purchased',
              'pricing_type': 'list',
              'tracking': 'none',
              'unit': 'pc',
              'vat_rate': '21',
            },
          ],
          'total': 1,
        },
        'GET /api/v1/price-zones': (_) => [
          _zone(),
          {'id': 'z2', 'code': 'Z2', 'name': 'Wholesale', 'sort_order': 2},
        ],
        'GET /api/v1/price-lists/pl1/exports': (_) => exports,
        'POST /api/v1/price-lists/pl1/render': (_) => Uint8List.fromList([1, 2, 3]),
      });
    });

    testWidgets('shows the tree, hidden-title groups and items in sort-key order', (
      tester,
    ) async {
      await _pump(tester, http, start: '/price-lists/pl1');
      Finder row(String id, String text) => find.descendant(
        of: find.byKey(ValueKey('plg-row-$id')),
        matching: find.textContaining(text),
      );
      expect(row('g1', 'Pumps'), findsOneWidget);
      expect(row('g3', 'Spacer'), findsOneWidget);
      expect(row('g3', 'title not printed · 8.50 mm'), findsOneWidget);
      final p2 = tester.getTopLeft(find.text('P-2 · Name P-2')).dy;
      final p10 = tester.getTopLeft(find.text('P-10 · Name P-10')).dy;
      expect(p2, lessThan(p10));
    });

    testWidgets('the gap field is enabled only while the title is hidden', (
      tester,
    ) async {
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('plg-add')));
      await tester.pumpAndSettle();
      TextField gap() => tester.widget(find.byKey(const ValueKey('plg-gap')));
      expect(gap().enabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('plg-show-title')));
      await tester.pumpAndSettle();
      expect(gap().enabled, isTrue);

      await tester.tap(find.byKey(const ValueKey('plg-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Enter a title in at least one language.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('plg-title-nl')), 'Gap');
      await tester.enterText(find.byKey(const ValueKey('plg-gap')), '80');
      await tester.tap(find.byKey(const ValueKey('plg-ok')));
      await tester.pumpAndSettle();
      expect(find.text('The gap must be a number from 0 to 50.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('plg-gap')), '12.5');
      await tester.tap(find.byKey(const ValueKey('plg-page-break')));
      await tester.tap(find.byKey(const ValueKey('plg-ok')));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/price-lists/pl1/groups'], {
        'sort_order': 40,
        'title': {'nl': 'Gap'},
        'page_break': true,
        'show_title': false,
        'gap_mm': '12.50',
      });
    });

    testWidgets('renames a group per language', (tester) async {
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('plg-edit-g2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('plg-title-en')), 'Taps');
      await tester.tap(find.byKey(const ValueKey('plg-ok')));
      await tester.pumpAndSettle();
      expect(
        (http.bodies['PUT /api/v1/price-lists/pl1/groups/g2']! as Map)['title'],
        {'nl': 'Valves', 'en': 'Taps'},
      );
    });

    testWidgets('moves a group up (renumbering) and nests it under the one above', (
      tester,
    ) async {
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('plg-up-g2')));
      await tester.pumpAndSettle();
      expect((http.bodies['PUT /api/v1/price-lists/pl1/groups/g2']! as Map)['sort_order'], 10);
      expect((http.bodies['PUT /api/v1/price-lists/pl1/groups/g1']! as Map)['sort_order'], 20);
      expect(http.requests, isNot(contains('PUT /api/v1/price-lists/pl1/groups/g3')));

      http.bodies.clear();
      await tester.tap(find.byKey(const ValueKey('plg-in-g2')));
      await tester.pumpAndSettle();
      final body = http.bodies['PUT /api/v1/price-lists/pl1/groups/g2']! as Map;
      expect(body['parent_id'], 'g1');
      expect(body['page_break'], false);
    });

    testWidgets('refuses to nest beyond four levels', (tester) async {
      groups = [
        _group('g1', 'L1', sort: 10),
        _group('g2', 'L2', parent: 'g1'),
        _group('g3', 'L3', parent: 'g2'),
        _group('g4', 'L4', parent: 'g3'),
      ];
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('plg-sub-g4')));
      await tester.pumpAndSettle();
      expect(find.text('Groups can be nested at most four levels deep.'), findsOneWidget);
      expect(http.requests, isNot(contains('POST /api/v1/price-lists/pl1/groups')));
    });

    testWidgets('adds a product to the chosen group', (tester) async {
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('pli-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valves').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Add product'), 'new');
      await tester.pumpAndSettle();
      await tester.tap(find.text('NEW-1 · Brand new'));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/price-lists/pl1/items'], {
        'product_id': 'p-NEW',
        'group_id': 'g2',
      });
    });

    testWidgets('edits flags, group, sort key and description of an item; removes one', (
      tester,
    ) async {
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('pli-edit-P-2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pli-sort-key')), '1..x');
      await tester.tap(find.byKey(const ValueKey('pli-ok')));
      await tester.pumpAndSettle();
      expect(find.text('Use dotted letters and digits, for example 2.10.3.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pli-sort-key')), '3.1');
      await tester.tap(find.byKey(const ValueKey('pli-net')));
      await tester.tap(find.byKey(const ValueKey('pli-hidden')));
      await tester.enterText(find.byKey(const ValueKey('pli-desc-en')), 'Small pump');
      await tester.tap(find.byKey(const ValueKey('pli-group')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Valves').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pli-ok')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/price-lists/pl1/items/i1'], {
        'group_id': 'g2',
        'sort_key': '3.1',
        'price_on_request': false,
        'net': true,
        'indicative': false,
        'hidden': true,
        'description': {'en': 'Small pump'},
      });

      await tester.tap(find.byKey(const ValueKey('pli-del-P-2')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/price-lists/pl1/items/i1'));
    });

    testWidgets('zones: add, choose languages, reorder and remove', (tester) async {
      http.routes['PUT /api/v1/price-lists/pl1/zones'] = (_) => _list();
      await _pump(tester, http, start: '/price-lists/pl1');
      expect(find.byKey(const ValueKey('plz-Z1')), findsOneWidget);

      // A zone keeps its last language.
      final nl = tester.widget<FilterChip>(find.byKey(const ValueKey('plz-Z1-nl')));
      expect(nl.selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('plz-Z1-fr')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/price-lists/pl1/zones'], [
        {'price_zone_id': 'z1', 'languages': ['nl', 'fr', 'en']},
      ]);

      await tester.tap(find.byKey(const ValueKey('plz-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Z2  Wholesale').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plz-add')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/price-lists/pl1/zones'], [
        {'price_zone_id': 'z1', 'languages': ['nl', 'en']},
        {'price_zone_id': 'z2', 'languages': ['nl', 'en']},
      ]);

      await tester.tap(find.byKey(const ValueKey('plz-del-Z1')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/price-lists/pl1/zones'], <Object?>[]);
    });

    testWidgets('zones: moving a zone down sends the new print order', (tester) async {
      http.routes['GET /api/v1/price-lists/pl1'] = (_) => _list(
        zones: [
          _plZone('z1', 'Z1', 'Retail', ['nl'], 1),
          _plZone('z2', 'Z2', 'Wholesale', ['en', 'de'], 2),
        ],
      );
      http.routes['PUT /api/v1/price-lists/pl1/zones'] = (_) => _list();
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('plz-down-Z1')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/price-lists/pl1/zones'], [
        {'price_zone_id': 'z2', 'languages': ['en', 'de']},
        {'price_zone_id': 'z1', 'languages': ['nl']},
      ]);
    });

    testWidgets('export profiles: create with chapters and a file name template', (
      tester,
    ) async {
      http.routes['POST /api/v1/price-lists/pl1/exports'] = (b) {
        final m = b! as Map;
        exports.add(_export('e1', m['code']! as String, m['name']! as String,
            groups: List<String>.from(m['group_ids'] as List), file: m['file_name'] as String?));
        return exports.last;
      };
      await _pump(tester, http, start: '/price-lists/pl1');
      expect(find.byKey(const ValueKey('ple-exp-none')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('ple-exp-add')));
      await tester.tap(find.byKey(const ValueKey('ple-exp-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pe-save')));
      await tester.pumpAndSettle();
      expect(find.text('Code and name are required.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('pe-name')), 'Pumps and valves');
      await tester.enterText(find.byKey(const ValueKey('pe-code')), 'PV');
      // Ticked in the opposite order: the request still lists them in print order.
      await tester.tap(find.byKey(const ValueKey('pe-group-g2')));
      await tester.tap(find.byKey(const ValueKey('pe-group-g1')));
      await tester.enterText(find.byKey(const ValueKey('pe-file')), '{list}-{zone}-{lang}-{code}');
      await tester.tap(find.byKey(const ValueKey('pe-save')));
      await tester.pumpAndSettle();
      expect(http.bodies['POST /api/v1/price-lists/pl1/exports'], {
        'code': 'PV',
        'name': 'Pumps and valves',
        'group_ids': ['g1', 'g2'],
        'file_name': '{list}-{zone}-{lang}-{code}',
      });
      expect(find.text('Pumps and valves  (PV)'), findsOneWidget);
      expect(find.textContaining('Pumps, Valves'), findsOneWidget);
    });

    testWidgets('export profiles: one per chapter, edit and delete', (tester) async {
      http.routes['POST /api/v1/price-lists/pl1/exports/per-chapter'] = (_) {
        exports = [
          _export('e1', 'ch-1', 'Pumps', groups: ['g1']),
          _export('e2', 'ch-2', 'Valves', groups: ['g2']),
        ];
        return exports;
      };
      http.routes['PUT /api/v1/price-lists/pl1/exports/e2'] = (_) => exports[1];
      http.routes['DELETE /api/v1/price-lists/pl1/exports/e1'] = (_) {
        exports.removeAt(0);
        return null;
      };
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.ensureVisible(find.byKey(const ValueKey('ple-exp-per-chapter')));
      await tester.tap(find.byKey(const ValueKey('ple-exp-per-chapter')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('POST /api/v1/price-lists/pl1/exports/per-chapter'));
      expect(find.text('Valves  (ch-2)'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ple-exp-edit-ch-2')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pe-name')), 'Taps');
      await tester.tap(find.byKey(const ValueKey('pe-save')));
      await tester.pumpAndSettle();
      expect(
        (http.bodies['PUT /api/v1/price-lists/pl1/exports/e2']! as Map)['name'],
        'Taps',
      );

      await tester.tap(find.byKey(const ValueKey('ple-exp-del-ch-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ple-exp-delete-confirm')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/price-lists/pl1/exports/e1'));
      expect(find.text('Pumps  (ch-1)'), findsNothing);
    });

    testWidgets('deleting a group used by an export profile shows the server message', (
      tester,
    ) async {
      http.routes['DELETE /api/v1/price-lists/pl1/groups/g2'] = (_) => const FakeStatus(
        409,
        {'error': 'conflict', 'message': 'Group is used by export profiles: Valves only'},
      );
      await _pump(tester, http, start: '/price-lists/pl1');
      await tester.tap(find.byKey(const ValueKey('plg-del-g2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('plg-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Group is in use'), findsOneWidget);
      expect(
        find.text('Group is used by export profiles: Valves only'),
        findsOneWidget,
      );
    });

    group('generate dialog', () {
      late List<(String, String)> written;
      late List<String> opened;

      List<Override> fakes({Set<String> failing = const {}}) {
        written = [];
        opened = [];
        return [
          fileExportProvider.overrideWithValue(
            FileExport(
              downloads: () async => '/dl',
              fallback: (_, _) async => true,
              writer: (base, rel, bytes) async {
                if (failing.contains(rel)) throw StateError('disk full');
                written.add((base, rel));
                return '$base/$rel';
              },
            ),
          ),
          downloadsFolderProvider.overrideWithValue(() async => '/dl'),
          pathOpenerProvider.overrideWithValue((p) async => opened.add(p)),
        ];
      }

      void routes() {
        exports = [_export('e1', 'ch-1', 'Pumps', groups: ['g1'])];
        http.routes['GET /api/v1/price-lists/pl1/export-plan'] = (_) {
          final x = http.queries.last['format'] == 'xlsx';
          final ext = x ? 'xlsx' : 'pdf';
          final f = x ? 'xlsx' : 'pdf';
          return [
            _planEntry('Z1', 'nl', null, 'PL/Z1/nl/PL.$ext', format: f),
            _planEntry('Z1', 'nl', 'e1', 'PL/Z1/nl/Pumps.$ext', format: f),
            _planEntry('Z1', 'en', null, 'PL/Z1/en/PL.$ext', format: f),
            _planEntry('Z1', 'en', 'e1', 'PL/Z1/en/Pumps.$ext', format: f),
          ];
        };
      }

      Future<void> open(WidgetTester tester, List<Override> o) async {
        await _pump(tester, http, start: '/price-lists/pl1', overrides: o);
        await tester.tap(find.byKey(const ValueKey('ple-generate')));
        await tester.pumpAndSettle();
      }

      testWidgets('shows the plan ticked, unticking a language drops its files, writes the rest', (
        tester,
      ) async {
        routes();
        await open(tester, fakes());
        expect(find.byKey(const ValueKey('plgen-file-3')), findsOneWidget);
        Finder inDialog(String t) =>
            find.descendant(of: find.byType(AlertDialog), matching: find.text(t));
        expect(inDialog('Whole list'), findsNWidgets(2));
        expect(inDialog('Pumps'), findsNWidgets(2));
        expect(http.queries.firstWhere((q) => q.containsKey('format'))['format'], 'pdf');

        await tester.tap(find.byKey(const ValueKey('plgen-lang-Z1-en')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('plgen-go')));
        await tester.pumpAndSettle();

        expect(written, [
          ('/dl', 'PL/Z1/nl/PL.pdf'),
          ('/dl', 'PL/Z1/nl/Pumps.pdf'),
        ]);
        final renders = [
          for (var i = 0; i < http.requests.length; i++)
            if (http.requests[i] == 'POST /api/v1/price-lists/pl1/render')
              http.queries[i],
        ];
        expect(renders, [
          {'zone_id': 'z-Z1', 'lang': 'nl', 'format': 'pdf'},
          {'zone_id': 'z-Z1', 'lang': 'nl', 'export_id': 'e1', 'format': 'pdf'},
        ]);
        expect(find.text('2 of 2 files saved'), findsOneWidget);
        expect(find.text('Folder: /dl'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('plgen-open')));
        expect(opened, ['/dl']);
      });

      testWidgets('Excel asks for the xlsx plan; one failing file does not stop the others', (
        tester,
      ) async {
        routes();
        await open(tester, fakes(failing: {'PL/Z1/nl/Pumps.xlsx'}));
        await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('plgen-format')),
          matching: find.text('Excel'),
        ));
        await tester.pumpAndSettle();
        expect(find.text('PL/Z1/nl/PL.xlsx'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('plgen-go')));
        await tester.pumpAndSettle();
        expect(written.length, 3);
        expect(find.text('3 of 4 files saved'), findsOneWidget);
        expect(find.textContaining('PL/Z1/nl/Pumps.xlsx: Bad state: disk full'), findsOneWidget);
      });

      testWidgets('an empty plan says so and cannot be generated', (tester) async {
        routes();
        http.routes['GET /api/v1/price-lists/pl1/export-plan'] = (_) => [];
        await open(tester, fakes());
        expect(find.byKey(const ValueKey('plgen-empty')), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byKey(const ValueKey('plgen-go'))).onPressed,
          isNull,
        );
      });
    });

    test('generateFiles reports per-file results in order', () async {
      final plan = [
        ExportPlanEntry.fromJson(_planEntry('Z1', 'nl', null, 'a/1.pdf')),
        ExportPlanEntry.fromJson(_planEntry('Z1', 'nl', 'e', 'a/2.pdf')),
        ExportPlanEntry.fromJson(_planEntry('Z1', 'en', null, 'a/3.pdf')),
      ];
      final saved = <String>[];
      final progress = <int>[];
      final out = await generateFiles(
        entries: plan,
        baseFolder: '/target',
        render: (e) async {
          if (e.relativePath == 'a/2.pdf') throw StateError('render failed');
          return Uint8List(2);
        },
        export: FileExport(
          downloads: () async => '/dl',
          fallback: (_, _) async => true,
          writer: (base, rel, _) async {
            saved.add('$base:$rel');
            return '$base/$rel';
          },
        ),
        onProgress: (d, _) => progress.add(d),
      );
      expect(saved, ['/target:a/1.pdf', '/target:a/3.pdf']);
      expect(progress, [0, 1, 2]);
      expect(out.map((r) => r.ok), [true, false, true]);
      expect(out[1].error, 'Bad state: render failed');
      final tree = groupPlan(plan);
      expect(tree.single.languages.keys, ['nl', 'en']);
      expect(tree.single.languages['nl'], [0, 1]);
    });

    testWidgets('a reader cannot edit', (tester) async {
      http.routes['GET /api/v1/me'] = (_) => meJson(['price_lists.read']);
      await _pump(tester, http, start: '/price-lists/pl1');
      expect(find.byKey(const ValueKey('plg-add')), findsNothing);
      expect(find.byKey(const ValueKey('plg-edit-g1')), findsNothing);
      expect(find.byKey(const ValueKey('pli-edit-P-2')), findsNothing);
      expect(find.byKey(const ValueKey('ple-generate')), findsOneWidget);
    });
  });

  group('company logo', () {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 0,
    ]);

    Future<FakeHttp> open(
      WidgetTester tester, {
      required PickedFile? picked,
      bool hasLogo = false,
      List<String> perms = const ['users.admin'],
    }) async {
      var logo = hasLogo;
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(perms),
        'GET /api/v1/admin/company/logo': (_) => logo
            ? png
            : const FakeStatus(404, {'error': 'not_found', 'message': 'no logo'}),
        'PUT /api/v1/admin/company/logo': (_) {
          logo = true;
          return {
            'content_type': 'image/png',
            'size_bytes': 12,
            'updated_at': '2027-01-01T00:00:00Z',
          };
        },
        'DELETE /api/v1/admin/company/logo': (_) {
          logo = false;
          return null;
        },
      });
      await _pump(
        tester,
        http,
        start: '/admin',
        overrides: [logoPickerProvider.overrideWithValue(() async => picked)],
      );
      await tester.tap(find.text('Company'));
      await tester.pumpAndSettle();
      return http;
    }

    testWidgets('rejects a wrong type and an oversized file before uploading', (
      tester,
    ) async {
      var http = await open(
        tester,
        picked: (name: 'x.gif', bytes: Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39])),
      );
      expect(find.byKey(const ValueKey('logo-none')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('logo-choose')));
      await tester.pumpAndSettle();
      expect(find.text('Only PNG, JPEG or SVG files are accepted.'), findsOneWidget);
      expect(http.requests, isNot(contains('PUT /api/v1/admin/company/logo')));

      final big = Uint8List(512 * 1024 + 1)..setAll(0, png);
      http = await open(tester, picked: (name: 'big.png', bytes: big));
      await tester.tap(find.byKey(const ValueKey('logo-choose')));
      await tester.pumpAndSettle();
      expect(find.text('The file is larger than 512 KB.'), findsOneWidget);
      expect(http.requests, isNot(contains('PUT /api/v1/admin/company/logo')));
    });

    testWidgets('uploads a PNG, shows the preview and removes it', (tester) async {
      final http = await open(tester, picked: (name: 'logo.png', bytes: png));
      await tester.tap(find.byKey(const ValueKey('logo-choose')));
      await tester.pumpAndSettle();
      expect(http.bodies['PUT /api/v1/admin/company/logo'], png);
      expect(find.byKey(const ValueKey('logo-preview')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('logo-remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('logo-remove-confirm')));
      await tester.pumpAndSettle();
      expect(http.requests, contains('DELETE /api/v1/admin/company/logo'));
      expect(find.byKey(const ValueKey('logo-none')), findsOneWidget);
    });

    testWidgets('is hidden from users without users.admin', (tester) async {
      final http = FakeHttp({
        'GET /api/v1/me': (_) => meJson(['prices.write']),
        'GET /api/v1/price-zones': (_) => [],
      });
      await _pump(tester, http, start: '/admin');
      expect(find.text('Company'), findsNothing);
      expect(http.requests, isNot(contains('GET /api/v1/admin/company/logo')));
    });
  });
}
