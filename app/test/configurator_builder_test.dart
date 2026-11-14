import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/configurator/builder/builder_pages.dart';
import 'package:tradocraft_app/features/configurator/builder/draft.dart';
import 'package:tradocraft_app/features/configurator/builder/editor_state.dart';
import 'package:tradocraft_app/features/configurator/builder/formula_editor.dart';
import 'package:tradocraft_app/features/configurator/builder/revision_editor.dart';
import 'package:tradocraft_app/features/configurator/builder/tables_tab.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';

import 'fake_http.dart';

Map<String, Object?> _seed() =>
    (jsonDecode(
          File('../seed/configurators/conveyor_line.json').readAsStringSync(),
        ) as Map<String, Object?>)['definition']
        as Map<String, Object?>;

Map<String, Object?> _revision(
  Object? definition, {
  String status = 'draft',
  List<Object?> errors = const [],
  String updated = '2026-11-08T10:00:00Z',
}) => {
  'id': 'rev1',
  'model_id': 'm1',
  'model_code': 'CONVEYOR-LINE',
  'model_name': 'Conveyor line',
  'revision': 2,
  'status': status,
  'notes': '',
  'definition': definition,
  'errors': errors,
  'created_at': '2026-11-08T10:00:00Z',
  'updated_at': updated,
};

/// A fake server for the editor: the revision, saving, formula checks and functions.
FakeHttp _server(
  Object? definition, {
  List<Object?> errors = const [],
  Object? Function(Object? body)? check,
}) {
  late FakeHttp http;
  http = FakeHttp({
    'GET /api/v1/configurator/revisions/rev1': (_) =>
        _revision(definition, errors: errors),
    'PUT /api/v1/configurator/revisions/rev1': (body) =>
        _revision((body as Map)['definition'], errors: errors),
    'GET /api/v1/configurator/functions': (_) => [
      {
        'name': 'lookup',
        'usage': 'lookup(table, {keys}, offset?)',
        'group': 'tables',
        'description': 'A row of a lookup table',
      },
      {
        'name': 'length',
        'usage': 'length(list)',
        'group': 'lists',
        'description': 'Number of elements',
      },
    ],
    'POST /api/v1/configurator/expressions/check':
        check ?? (_) => {'ok': true, 'type': 'decimal', 'errors': <Object?>[]},
    'POST /api/v1/configurator/revisions/rev1/evaluate': (_) => {
      'project': <Object?>[],
      'groups': <Object?>[],
      'items': <Object?>[],
      'lines': <Object?>[],
      'issues': <Object?>[],
      'steps': 1,
    },
  });
  return http;
}

Future<ProviderContainer> _pumpEditor(
  WidgetTester tester,
  FakeHttp http, {
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1700, 1300);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [dioProvider.overrideWithValue(fakeDio(http)), ...overrides],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RevisionEditorScreen(id: 'rev1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

EditorState _state(ProviderContainer c) =>
    c.read(revisionEditorProvider('rev1'));

Map<String, Object?> _field(ProviderContainer c, String scope, int i) {
  final d = _state(c).draft!;
  final s = scope == 'project'
      ? const ScopeSel.project()
      : scope == 'group'
      ? const ScopeSel.group()
      : const ScopeSel.item(0);
  return jsonList(d.readScope(s), 'fields')[i];
}

void main() {
  setUp(() => FormulaField.checkDelay = const Duration(milliseconds: 10));

  // -------------------------------------------------------------------------------------------
  // The draft model
  // -------------------------------------------------------------------------------------------

  group('definition draft', () {
    test('the demo definition round-trips unchanged', () {
      final seed = _seed();
      final d = DefinitionDraft(seed);
      expect(jsonEquals(d.toJson(), seed), isTrue);
      expect(jsonEncode(d.toJson()), jsonEncode(seed));
      // Reading through every helper changes nothing either.
      for (final s in d.scopes()) {
        d.readScope(s);
        d.namesFor(s, inRule: true);
      }
      d.rule([1, 0]);
      d.tableColumns('motors');
      expect(jsonEncode(d.toJson()), jsonEncode(seed));
    });

    test('cleared properties are removed, so defaults apply', () {
      final f = <String, Object?>{'name': 'x', 'type': 'number', 'min': 1};
      setProp(f, 'min', null);
      setProp(f, 'help', '');
      setProp(f, 'display_units', <Object?>[]);
      expect(f, {'name': 'x', 'type': 'number'});
    });

    test('names a formula can use, per scope', () {
      final d = DefinitionDraft(_seed());
      final item = d.namesFor(const ScopeSel.item(0)).map((n) => n.name);
      expect(item, containsAll(['length_m', 'power_kw', 'voltage', 'phases']));
      expect(item, contains('index'));
      expect(item, contains('motors'));
      final project = d.namesFor(const ScopeSel.project()).map((n) => n.name);
      expect(project, containsAll(['segments', 'items', 'total_length']));
      expect(project, isNot(contains('length_m')));
    });

    test('JSON paths of server errors map to editor locations', () {
      var l = locate(r'$.item_tables[0].computed[1].expr');
      expect(l.tab, EditorTab.computed);
      expect(l.scope, const ScopeSel.item(0));
      expect((l.index, l.property), (1, 'expr'));
      l = locate(r'$.project.fields[2].name');
      expect(
        (l.tab, l.scope, l.index, l.property),
        (EditorTab.fields, const ScopeSel.project(), 2, 'name'),
      );
      l = locate(r'$.outputs[1].children[0].percent_of_parent');
      expect((l.tab, l.property), (EditorTab.outputs, 'percent_of_parent'));
      expect(l.rule, [1, 0]);
      l = locate(r'$.tables[0].rows[3].kw_max');
      expect(
        (l.tab, l.index, l.row, l.property),
        (EditorTab.tables, 0, 3, 'kw_max'),
      );
      l = locate(r'$.validations[2].when');
      expect((l.tab, l.index, l.property), (EditorTab.validations, 2, 'when'));
      l = locate(r'$.item_tables[0].min_rows');
      expect(
        (l.tab, l.scope, l.index, l.property),
        (EditorTab.fields, const ScopeSel.item(0), null, 'min_rows'),
      );
      expect(locate(r'$.name').tab, EditorTab.general);
      expect(locate(r'$').tab, EditorTab.general);
    });

    test('table CSV round trip keeps rows and types', () {
      final table = DefinitionDraft(_seed()).tables().first;
      final csv = tableToCsv(table);
      expect(csv.split('\n').first, 'phases,kw_min,kw_max,size,code');
      final back = csvToRows(csv, table);
      expect(back.errors, isEmpty);
      expect(jsonEncode(back.rows), jsonEncode(table['rows']));
      // Semicolons, quotes and bad values.
      final r = csvToRows(
        'phases;kw_min;kw_max;size;code\n3;0;1.5;"0;5";X\nthree;0;1;a;b\n',
        table,
      );
      expect(r.errors, ['line 3, phases: "three"']);
      expect(r.rows.first, {
        'phases': 3,
        'kw_min': 0,
        'kw_max': 1.5,
        'size': '0;5',
        'code': 'X',
      });
      expect(csvToRows('nope\n1\n', table).errors, ['unknown column "nope"']);
      // An unclosed quote does not swallow the following rows.
      final open = csvToRows('phases,size\n3,"05\n1,22\n', table);
      expect(open.rows, isEmpty);
      expect(open.errors, ['line 2: a quoted cell is not closed']);
    });

    test('a column rename does not overwrite another column', () {
      final table = <String, Object?>{
        'columns': [
          {'name': 'a', 'type': 'text'},
          {'name': 'b', 'type': 'text'},
        ],
        'rows': [
          {'a': 'x', 'b': 'y'},
        ],
      };
      // Typing "bc" passes through "b": not applied until the name is unique.
      expect(renameColumn(table, 0, 'b'), isFalse);
      expect(renameColumn(table, 0, 'bc'), isTrue);
      expect((table['rows'] as List).first, {'bc': 'x', 'b': 'y'});
    });

    test('suggestions: names first, then functions, by prefix', () {
      final s = suggestionsFor(
        'len',
        const [NameHint('length_m', 'field'), NameHint('load_kg', 'field')],
        [
          Signature.fromJson({
            'name': 'length',
            'usage': 'length(l)',
            'group': 'lists',
            'description': '',
          }),
        ],
      );
      expect(s.map((x) => x.name), ['length_m', 'length']);
      expect(s.last.insert, 'length(');
      expect(insideTemplateExpr('DRV-{mot', 8), isTrue);
      expect(insideTemplateExpr('DRV-{a} x', 9), isFalse);
      expect(wordBefore('a + motor_s', 11), (start: 4, prefix: 'motor_s'));
    });
  });

  // -------------------------------------------------------------------------------------------
  // The editor
  // -------------------------------------------------------------------------------------------

  testWidgets('viewing every tab leaves the definition unchanged', (
    tester,
  ) async {
    final seed = _seed();
    final http = _server(seed);
    final c = await _pumpEditor(tester, http);
    expect(find.text('Conveyor line'), findsOneWidget);
    for (final t in EditorTab.values) {
      await tester.tap(find.byKey(ValueKey('tab-${t.name}')));
      await tester.pumpAndSettle();
    }
    // Open a few elements too.
    await tester.tap(find.byKey(const ValueKey('tab-outputs')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('motor_coating'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rule-editor')), findsOneWidget);
    expect(_state(c).dirty, isFalse);
    expect(jsonEncode(_state(c).draft!.toJson()), jsonEncode(seed));
    // Saving sends it back as loaded.
    await tester.tap(find.byKey(const ValueKey('save-draft')));
    await tester.pumpAndSettle();
    expect(
      jsonEncode(
        (http.bodies['PUT /api/v1/configurator/revisions/rev1']
            as Map)['definition'],
      ),
      jsonEncode(seed),
    );
  });

  testWidgets('field editor shows the properties of the field type', (
    tester,
  ) async {
    final c = await _pumpEditor(tester, _server(_seed()));
    // Project field "voltage" (index 1) is a number with a dimension.
    await tester.tap(find.text('voltage').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('number-props')), findsOneWidget);
    expect(find.byKey(const ValueKey('display-units')), findsOneWidget);
    expect(find.byKey(const ValueKey('choice-props')), findsNothing);
    expect(find.widgetWithText(TextField, '690'), findsOneWidget);

    // Change the maximum.
    await tester.enterText(find.widgetWithText(TextField, '690'), '1000');
    await tester.pump();
    expect(_field(c, 'project', 1)['max'], 1000);

    // Make it a choice: number properties go, options come.
    await tester.tap(find.byKey(const ValueKey('field-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choice').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('choice-props')), findsOneWidget);
    expect(find.byKey(const ValueKey('number-props')), findsNothing);
    final f = _field(c, 'project', 1);
    expect(f['type'], 'choice');
    expect(f.containsKey('max'), isFalse);
    expect(f.containsKey('unit'), isFalse);
    expect(f.containsKey('default'), isFalse);
    await tester.tap(find.byKey(const ValueKey('add-option')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byKey(const ValueKey('option-0')),
            matching: find.byType(TextField),
          )
          .first,
      '230',
    );
    await tester.pump();
    expect(_field(c, 'project', 1)['options'], [
      {'value': 230},
    ]);
    expect(_state(c).dirty, isTrue);

    // A text field has a maximum length and pattern.
    await tester.tap(find.byKey(const ValueKey('field-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text').last);
    await tester.pumpAndSettle();
    expect(find.text('Maximum length'), findsOneWidget);
    expect(find.text('Pattern (regular expression)'), findsOneWidget);
    expect(_field(c, 'project', 1).containsKey('options'), isFalse);
  });

  testWidgets('fields are reordered by dragging', (tester) async {
    final c = await _pumpEditor(tester, _server(_seed()));
    List<Object?> names() => [
      for (final f in jsonList(
        _state(c).draft!.readScope(const ScopeSel.project()),
        'fields',
      ))
        f['name'],
    ];
    expect(names().take(2), ['phases', 'voltage']);
    final handle = find.descendant(
      of: find.byKey(const ValueKey('fields-project-0-phases')),
      matching: find.byIcon(Icons.drag_handle),
    );
    final drag = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(kLongPressTimeout);
    final h = tester
        .getSize(find.byKey(const ValueKey('fields-project-0-phases')))
        .height;
    for (var moved = 0.0; moved < h * 1.1; moved += 4) {
      await drag.moveBy(const Offset(0, 4));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(names().take(2), ['voltage', 'phases']);
  });

  testWidgets('formula editor completes names and functions', (tester) async {
    final c = await _pumpEditor(tester, _server(_seed()));
    await tester.tap(find.byKey(const ValueKey('tab-computed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-item:0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('power_kw').first);
    await tester.pumpAndSettle();
    final formula = find.byKey(
      const ValueKey(r'$.item_tables[0].computed[0].expr'),
    );
    final field = find.descendant(
      of: formula,
      matching: find.byType(TextField),
    );
    await tester.tap(field);
    await tester.enterText(field, 'len');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('formula-suggestions')), findsOneWidget);
    expect(find.text('length_m'), findsWidgets);
    expect(find.text('length(list)'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('formula-suggestions')),
        matching: find.text('length_m'),
      ),
    );
    await tester.pumpAndSettle();
    final ctrl = tester.widget<TextField>(field).controller!;
    expect(ctrl.text, 'length_m');
    expect(
      jsonList(
        _state(c).draft!.readScope(const ScopeSel.item(0)),
        'computed',
      )[0]['expr'],
      'length_m',
    );
    // A function is inserted with its bracket.
    await tester.enterText(field, 'length_m * look');
    await tester.pumpAndSettle();
    await tester.tap(find.text('lookup'));
    await tester.pumpAndSettle();
    expect(ctrl.text, 'length_m * lookup(');
  });

  testWidgets('formula editor highlights the problem range from the check', (
    tester,
  ) async {
    Object? sent;
    final http = _server(
      _seed(),
      check: (body) {
        sent = body;
        final src = (body as Map)['source'] as String;
        return src.contains('lenght')
            ? {
                'ok': false,
                'type': 'any',
                'errors': [
                  {'message': 'unknown name lenght_m', 'start': 0, 'end': 8},
                ],
              }
            : {'ok': true, 'type': 'decimal', 'errors': <Object?>[]};
      },
    );
    await _pumpEditor(tester, http);
    await tester.tap(find.byKey(const ValueKey('tab-computed')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('scope-item:0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('power_kw').first);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byKey(const ValueKey(r'$.item_tables[0].computed[0].expr')),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, 'lenght_m * 2');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('unknown name lenght_m'), findsOneWidget);
    final ctrl =
        tester.widget<TextField>(field).controller! as FormulaController;
    expect(ctrl.problems.single.start, 0);
    expect(ctrl.problems.single.end, 8);
    // The highlighted span is the bad name only.
    final span = ctrl.buildTextSpan(
      context: tester.element(field),
      withComposing: false,
    );
    final marked = span.children!.cast<TextSpan>().firstWhere(
      (s) => s.style?.decoration == TextDecoration.underline,
    );
    expect(marked.text, 'lenght_m');
    // The check got the scope, table and the definition being edited.
    expect((sent as Map)['scope'], 'item');
    expect((sent as Map)['table'], 'segments');
    expect(((sent as Map)['definition'] as Map)['name'], 'Conveyor line');

    await tester.enterText(field, 'length_m * 2');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('unknown name lenght_m'), findsNothing);
    expect(find.text('Result: decimal'), findsOneWidget);
    expect(ctrl.problems, isEmpty);
  });

  testWidgets('table editor edits rows and columns and imports CSV', (
    tester,
  ) async {
    Uint8List? exported;
    final c = await _pumpEditor(
      tester,
      _server(_seed()),
      overrides: [
        csvPickerProvider.overrideWithValue(
          () async => (
            name: 'motors.csv',
            bytes: Uint8List.fromList(
              utf8.encode('phases,kw_min,kw_max,size,code\n3,0,9,99,MOT-999\n'),
            ),
          ),
        ),
        csvSaverProvider.overrideWithValue((name, bytes) async {
          exported = bytes;
          return true;
        }),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('tab-tables')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('motors'));
    await tester.pumpAndSettle();
    Map<String, Object?> table() => _state(c).draft!.tables().first;
    expect(find.byKey(const ValueKey('row-5')), findsOneWidget);

    // Edit a cell: typed by its column.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('cell-0-kw_max')),
        matching: find.byType(TextField),
      ),
      '0.6',
    );
    await tester.pump();
    expect(jsonList(table(), 'rows')[0]['kw_max'], 0.6);

    // Add a row and a column; rename the column.
    await tester.tap(find.byKey(const ValueKey('add-row')));
    await tester.pumpAndSettle();
    expect(jsonList(table(), 'rows'), hasLength(7));
    await tester.tap(find.byKey(const ValueKey('add-column')));
    await tester.pumpAndSettle();
    expect(jsonList(table(), 'columns').last, {
      'name': 'column',
      'type': 'text',
    });
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('col-name-5')),
        matching: find.byType(TextField),
      ),
      'note',
    );
    await tester.pump();
    expect(jsonList(table(), 'columns').last['name'], 'note');
    // Renaming a key column renames it in the keys and the rows.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('col-name-0')),
        matching: find.byType(TextField),
      ),
      'ph',
    );
    await tester.pump();
    expect(table()['keys'], ['ph']);
    expect(jsonList(table(), 'rows')[0]['ph'], 3);

    // Remove the new column again.
    await tester.tap(find.byKey(const ValueKey('col-remove-5')));
    await tester.pumpAndSettle();
    expect(jsonList(table(), 'columns'), hasLength(5));

    // CSV export, then import replacing the rows.
    await tester.tap(find.byKey(const ValueKey('csv-export')));
    await tester.pumpAndSettle();
    expect(
      utf8.decode(exported!).split('\n').first,
      'ph,kw_min,kw_max,size,code',
    );
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('col-name-0')),
        matching: find.byType(TextField),
      ),
      'phases',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('csv-import')));
    await tester.pumpAndSettle();
    expect(jsonList(table(), 'rows'), [
      {'phases': 3, 'kw_min': 0, 'kw_max': 9, 'size': '99', 'code': 'MOT-999'},
    ]);
    expect(find.text('1 row imported.'), findsOneWidget);
  });

  testWidgets('output rules are edited as a tree', (tester) async {
    final c = await _pumpEditor(tester, _server(_seed()));
    await tester.tap(find.byKey(const ValueKey('tab-outputs')));
    await tester.pumpAndSettle();
    DefinitionDraft d() => _state(c).draft!;
    expect(d().outputs(), hasLength(7));

    // A new top-level rule, then an option line below it.
    await tester.tap(find.byKey(const ValueKey('add-rule')));
    await tester.pumpAndSettle();
    expect(d().outputs().last, {'id': 'line', 'code': ''});
    expect(find.text('Output rule line'), findsOneWidget);
    expect(find.text('Percent of parent (formula)'), findsNothing);
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey(r'$.outputs[7].code')),
        matching: find.byType(TextField),
      ),
      "'GUARD-01'",
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('add-child-7')));
    await tester.pumpAndSettle();
    expect(find.text('Option line option'), findsOneWidget);
    expect(find.text('Percent of parent (formula)'), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byKey(
          const ValueKey(r'$.outputs[7].children[0].percent_of_parent'),
        ),
        matching: find.byType(TextField),
      ),
      '15',
    );
    await tester.pump();
    expect(d().rule([7]), {
      'id': 'line',
      'code': "'GUARD-01'",
      'children': [
        {'id': 'option', 'code': '', 'percent_of_parent': '15'},
      ],
    });

    // Code as a template.
    await tester.tap(find.byKey(const ValueKey('rule-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Product code (template)').first);
    await tester.pumpAndSettle();
    expect(d().rule([7])!.containsKey('code'), isFalse);
    expect(d().rule([7])!['code_template'], '');

    // Scope of a top-level rule.
    await tester.tap(find.byKey(const ValueKey('rule-scope')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Item (row)').last);
    await tester.pumpAndSettle();
    expect(d().rule([7])!['scope'], 'item');

    // Removing the parent removes its option line.
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('rule-7')),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(d().outputs(), hasLength(7));
  });

  testWidgets('server problems lead to the element in the editor', (
    tester,
  ) async {
    final seed = _seed();
    final c = await _pumpEditor(
      tester,
      _server(
        seed,
        errors: [
          {
            'path': r'$.item_tables[0].computed[2].options_from',
            'message': 'unknown name rws',
            'start': 4,
            'end': 7,
          },
          {
            'path': r'$.outputs[1].children[0].quantity',
            'message': 'not a number',
          },
        ],
      ),
    );
    expect(find.text('2 problems'), findsOneWidget);
    // The tabs with problems carry a badge.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('tab-computed')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('problems')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('unknown name rws'));
    await tester.pumpAndSettle();
    final s = _state(c);
    expect(s.tab, EditorTab.computed);
    expect((s.computedScope, s.computedIndex), (const ScopeSel.item(0), 2));
    expect(find.text('Computed value motor_code'), findsOneWidget);
    // The formula shows the saved problem.
    expect(find.text('unknown name rws'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('problems')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('not a number'));
    await tester.pumpAndSettle();
    expect(_state(c).tab, EditorTab.outputs);
    expect(_state(c).rulePath, [1, 0]);
    expect(find.text('Option line motor_coating'), findsOneWidget);
  });

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    final http = _server(_seed());
    tester.view.physicalSize = const Size(1700, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RevisionEditorScreen(id: 'rev1'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    container
        .read(revisionEditorProvider('rev1').notifier)
        .edit((d) => d.json['name'] = 'Changed');
    await tester.pump();
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    await nav.maybePop();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Unsaved changes'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(RevisionEditorScreen), findsOneWidget);
    await nav.maybePop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discard')));
    await tester.pumpAndSettle();
    expect(find.byType(RevisionEditorScreen), findsNothing);
    expect(
      http.requests,
      isNot(contains('PUT /api/v1/configurator/revisions/rev1')),
    );
  });

  testWidgets('an active revision is read-only', (tester) async {
    final http = _server(_seed());
    http.routes['GET /api/v1/configurator/revisions/rev1'] = (_) =>
        _revision(_seed(), status: 'active');
    await _pumpEditor(tester, http);
    expect(find.byKey(const ValueKey('save-draft')), findsNothing);
    expect(find.text('New draft from this revision'), findsOneWidget);
    await tester.tap(find.text('voltage').first);
    await tester.pumpAndSettle();
    final name = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('field-name')),
        matching: find.byType(TextField),
      ),
    );
    expect(name.enabled, isFalse);
  });

  testWidgets('designers create a configurator and land in its draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final http = FakeHttp({
      'GET /api/v1/configurator/models': (_) => [
        {
          'id': 'm1',
          'code': 'CONVEYOR-LINE',
          'name': 'Conveyor line',
          'description': '',
          'active': true,
          'active_revision': 1,
          'active_revision_id': 'r1',
          'draft_revision': 2,
          'draft_revision_id': 'r2',
          'updated_at': '2026-11-08T10:00:00Z',
        },
      ],
      'POST /api/v1/configurator/models': (body) => {
        'id': 'm2',
        'code': (body as Map)['code'],
        'name': body['name'],
        'description': '',
        'active': true,
        'translations': <String, Object?>{},
        'revisions': [
          {
            'id': 'r9',
            'model_id': 'm2',
            'revision': 1,
            'status': 'draft',
            'notes': '',
            'created_at': '2026-11-08T10:00:00Z',
          },
        ],
        'created_at': '2026-11-08T10:00:00Z',
        'updated_at': '2026-11-08T10:00:00Z',
      },
    });
    final router = GoRouter(
      initialLocation: '/configurator/builder',
      routes: [
        GoRoute(
          path: '/configurator/builder',
          builder: (_, _) => const BuilderModelsPage(),
        ),
        GoRoute(
          path: '/configurator/builder/revisions/:id',
          builder: (_, s) => Text('editor ${s.pathParameters['id']}'),
        ),
        GoRoute(
          path: '/configurator/builder/models/:id',
          builder: (_, s) => Text('model ${s.pathParameters['id']}'),
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
    expect(find.text('Conveyor line · CONVEYOR-LINE'), findsOneWidget);
    expect(
      find.text('active: revision 1 · draft: revision 2 · 08/11/2026'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('new-model')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('model-code')),
      'PUMP-SET',
    );
    await tester.enterText(
      find.byKey(const ValueKey('model-name')),
      'Pump set',
    );
    await tester.tap(find.byKey(const ValueKey('create-model')));
    await tester.pumpAndSettle();
    expect(
      (http.bodies['POST /api/v1/configurator/models'] as Map)['code'],
      'PUMP-SET',
    );
    expect(find.text('editor r9'), findsOneWidget);
  });
}
