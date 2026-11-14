import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart' hide Evaluation;
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/configurator/configurator_page.dart';
import 'package:tradocraft_app/features/configurator/definition.dart';
import 'package:tradocraft_app/features/configurator/runner_state.dart';
import 'package:tradocraft_app/features/configurator/widgets/field_widgets.dart';
import 'package:tradocraft_app/features/configurator/widgets/item_grid.dart';
import 'package:tradocraft_app/features/configurator/widgets/panels.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

// ---------------------------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------------------------

/// A definition with every field type, a group scope and an item table.
final _definition = <String, Object?>{
  'schema_version': 1,
  'name': 'Test',
  'sections': [
    {'name': 'main', 'label': 'Main'},
  ],
  'project': {
    'fields': [
      {
        'name': 'voltage',
        'type': 'number',
        'label': 'Voltage',
        'dimension': 'voltage',
        'unit': 'V',
        'display_units': ['V', 'kV'],
        'min': 100,
        'max': 690,
        'layout': {'section': 'main', 'order': 1},
      },
      {'name': 'count', 'type': 'integer', 'label': 'Count'},
      {'name': 'coating', 'type': 'boolean', 'label': 'Coating'},
      {
        'name': 'phases',
        'type': 'choice',
        'label': 'Phases',
        'options': [
          {'value': 1, 'label': 'Single phase'},
          {'value': 3, 'label': 'Three phase'},
        ],
      },
      {'name': 'note', 'type': 'text', 'label': 'Note'},
      {'name': 'extra', 'type': 'product', 'label': 'Extra product'},
      {
        'name': 'coating_class',
        'type': 'choice',
        'label': 'Coating class',
        'visible_if': 'coating',
        'options': [
          {'value': 'C3'},
          {'value': 'C4'},
        ],
      },
    ],
    'computed': [
      {'name': 'total', 'label': 'Total length', 'unit': 'm', 'expr': '1'},
      {
        'name': 'motor',
        'label': 'Motor',
        'expr': "'MOT-1'",
        'overridable': true,
        'options_from': "['MOT-1', 'MOT-2']",
      },
      {'name': 'helper', 'label': 'Helper', 'expr': '1', 'show': false},
    ],
  },
  'group': {
    'label': 'Hall',
    'fields': [
      {
        'name': 'voltage',
        'type': 'number',
        'unit': 'V',
        'label': 'Hall voltage',
      },
    ],
  },
  'item_tables': [
    {
      'name': 'segments',
      'label': 'Segment',
      'group_field': 'hall',
      'fields': [
        {'name': 'hall', 'type': 'text', 'label': 'Hall', 'default': 'Hall 1'},
        {
          'name': 'length_m',
          'type': 'number',
          'label': 'Length',
          'dimension': 'length',
          'unit': 'm',
          'display_units': ['m', 'mm'],
        },
        {'name': 'stop', 'type': 'boolean', 'label': 'Stop'},
      ],
      'computed': [
        {
          'name': 'motor_code',
          'label': 'Motor',
          'expr': "'MOT-1'",
          'overridable': true,
          'options_from': "['MOT-1', 'MOT-2']",
        },
      ],
    },
  ],
};

Map<String, Object?> _vr(
  String name,
  Object? value, {
  String source = 'input',
  bool visible = true,
  bool enabled = true,
  List<Object?>? options,
  Object? calculated,
  String kind = 'field',
}) => {
  'name': name,
  'kind': kind,
  'value': value,
  'source': source,
  'visible': visible,
  'enabled': enabled,
  'calculated': ?calculated,
  'options': ?options,
};

Evaluation _evaluation({
  List<Map<String, Object?>> project = const [],
  List<Map<String, Object?>> rows = const [],
  List<Map<String, Object?>> issues = const [],
  List<Map<String, Object?>> lines = const [],
  List<String> groups = const [],
}) => Evaluation.fromJson({
  'project': project,
  'groups': [
    for (final g in groups) {'name': g, 'values': <Object?>[]},
  ],
  'items': [
    {'table': 'segments', 'rows': rows},
  ],
  'lines': lines,
  'issues': issues,
  'steps': 1,
});

/// In-memory [RunnerActions] for widget tests.
class _FakeActions implements RunnerActions {
  _FakeActions(this.inputs);
  RunnerInputs inputs;
  final pins = <String, Object?>{};
  final unpinned = <String>[];
  final units = <String, String>{};
  VoidCallback? onChange;

  void _set(RunnerInputs i) {
    inputs = i;
    onChange?.call();
  }

  @override
  void setValue(FieldRef ref, Object? value) => _set(inputs.set(ref, value));
  @override
  void pin(FieldRef ref, Object? value) {
    pins[ref.key] = value;
    _set(inputs.pin(ref.pin(value, null)));
  }

  @override
  void unpin(FieldRef ref) {
    unpinned.add(ref.key);
    _set(inputs.unpin(ref));
  }

  @override
  void setDisplayUnit(String key, String unit) {
    units[key] = unit;
    onChange?.call();
  }

  @override
  void addRow(String table, [InputRow initial = const {}]) =>
      _set(inputs.addRow(table, initial));
  @override
  void duplicateRow(String table, int row) =>
      _set(inputs.duplicateRow(table, row));
  @override
  void deleteRow(String table, int row) => _set(inputs.deleteRow(table, row));
  @override
  void bulkSet(
    String table,
    String name,
    Object? value, {
    Iterable<int>? rows,
  }) => _set(inputs.bulkSet(table, name, value, rows: rows));
}

/// Renders [build] with a view over the fake actions; rebuilds on every change.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.actions,
    required this.evaluation,
    required this.build,
  });
  final _FakeActions actions;
  final Evaluation evaluation;
  final Widget Function(RunnerView view) build;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  void initState() {
    super.initState();
    widget.actions.onChange = () => setState(() {});
  }

  @override
  Widget build(BuildContext context) => widget.build(
    RunnerView(
      definition: CfgDefinition(_definition),
      inputs: widget.actions.inputs,
      index: EvalIndex(widget.evaluation),
      actions: widget.actions,
      displayUnits: widget.actions.units,
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<_FakeActions> _pumpProjectForm(
  WidgetTester tester,
  Evaluation evaluation, [
  RunnerInputs inputs = const RunnerInputs(),
]) async {
  final actions = _FakeActions(inputs);
  final def = CfgDefinition(_definition);
  await _pump(
    tester,
    _Harness(
      actions: actions,
      evaluation: evaluation,
      build: (view) => ConfigForm(
        view: view,
        scope: def.project,
        refOf: FieldRef.project,
        sections: def.sections,
      ),
    ),
  );
  return actions;
}

final _projectValues = [
  _vr('voltage', '400', source: 'default'),
  _vr('count', null, source: 'empty'),
  _vr('coating', false, source: 'default'),
  _vr('phases', 3, source: 'default', options: [1, 3]),
  _vr('note', null, source: 'empty'),
  _vr('extra', null, source: 'empty', options: ['ACC-1', 'ACC-2']),
  _vr(
    'coating_class',
    'C4',
    source: 'hidden',
    visible: false,
    options: ['C3', 'C4'],
  ),
  _vr('total', '12.5', source: 'calculated', kind: 'computed'),
  _vr(
    'motor',
    'MOT-1',
    source: 'calculated',
    kind: 'computed',
    options: ['MOT-1', 'MOT-2'],
  ),
];

Finder _field(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(TextField));

void main() {
  // -------------------------------------------------------------------------------------------
  // Inputs and state
  // -------------------------------------------------------------------------------------------
  group('RunnerInputs', () {
    test('sets and clears values at every scope', () {
      var i = const RunnerInputs()
          .set(const FieldRef.project('voltage'), '400')
          .set(const FieldRef.group('Hall 1', 'voltage'), '230')
          .addRow('segments', {'hall': 'Hall 1'})
          .set(const FieldRef.item('segments', 0, 'length_m'), '12');
      expect(i.toJson(), {
        'project': {'voltage': '400'},
        'groups': {
          'Hall 1': {'voltage': '230'},
        },
        'items': {
          'segments': [
            {'hall': 'Hall 1', 'length_m': '12'},
          ],
        },
        'pins': <Object?>[],
      });
      i = i.set(const FieldRef.project('voltage'), null);
      expect(i.project.containsKey('voltage'), isFalse);
      i = i.set(const FieldRef.item('segments', 0, 'length_m'), '');
      expect(i.rows('segments').single, {'hall': 'Hall 1'});
    });

    test('duplicating and deleting rows keeps pins on their rows', () {
      var i = const RunnerInputs()
          .addRow('segments', {'length_m': '1'})
          .addRow('segments', {'length_m': '2'})
          .addRow('segments', {'length_m': '3'});
      i = i
          .pin(
            const FieldRef.item(
              'segments',
              1,
              'motor_code',
            ).pin('MOT-2', 'MOT-1'),
          )
          .pin(
            const FieldRef.item(
              'segments',
              2,
              'motor_code',
            ).pin('MOT-3', 'MOT-1'),
          )
          .pin(const FieldRef.project('motor').pin('MOT-9', 'MOT-1'));

      final dup = i.duplicateRow('segments', 1);
      expect(
        [for (final r in dup.rows('segments')) r['length_m']],
        ['1', '2', '2', '3'],
      );
      expect(
        {for (final p in dup.pins) '${p.table}/${p.row}': p.value},
        {
          'segments/1': 'MOT-2',
          'segments/2': 'MOT-2',
          'segments/3': 'MOT-3',
          'null/null': 'MOT-9',
        },
      );
      // The copy is independent of the original.
      final edited = dup.set(
        const FieldRef.item('segments', 2, 'length_m'),
        '7',
      );
      expect(edited.rows('segments')[1]['length_m'], '2');

      final del = i.deleteRow('segments', 1);
      expect([for (final r in del.rows('segments')) r['length_m']], ['1', '3']);
      expect(
        {for (final p in del.pins) '${p.table}/${p.row}': p.value},
        {'segments/1': 'MOT-3', 'null/null': 'MOT-9'},
      );
    });

    test('bulk set, pin and unpin', () {
      var i = const RunnerInputs()
          .addRow('segments')
          .addRow('segments')
          .addRow('segments');
      i = i.bulkSet('segments', 'speed', '1.2');
      expect(i.rows('segments').every((r) => r['speed'] == '1.2'), isTrue);
      i = i.bulkSet('segments', 'speed', '2', rows: [2]);
      expect(
        [for (final r in i.rows('segments')) r['speed']],
        ['1.2', '1.2', '2'],
      );

      const ref = FieldRef.group('Hall 1', 'boards');
      i = i.pin(ref.pin(3, 2)).pin(ref.pin(4, 2));
      expect(i.pins, hasLength(1));
      expect(i.pinFor(ref)?.toJson(), {
        'name': 'boards',
        'group': 'Hall 1',
        'value': 4,
        'calculated': 2,
      });
      expect(i.unpin(ref).pins, isEmpty);
    });

    test('reads saved inputs', () {
      final i = RunnerInputs.fromApi(
        Inputs.fromJson({
          'project': {'phases': 3},
          'groups': {
            'A': {'voltage': '230'},
          },
          'items': {
            'segments': [
              {'hall': 'A'},
            ],
          },
          'pins': [
            {
              'name': 'motor_code',
              'table': 'segments',
              'row': 0,
              'value': 'MOT-2',
            },
          ],
        }),
      );
      expect(i.project['phases'], 3);
      expect(i.groups['A']!['voltage'], '230');
      expect(
        i.pinFor(const FieldRef.item('segments', 0, 'motor_code'))?.value,
        'MOT-2',
      );
    });
  });

  test('issues point at fields', () {
    Issue issue(String scope, String? field) => Issue.fromJson({
      'severity': 'warning',
      'code': 'x',
      'message': 'm',
      'scope': scope,
      'field': ?field,
    });
    expect(
      FieldRef.ofIssue(issue('project', 'voltage'))?.key,
      'project/voltage',
    );
    expect(
      FieldRef.ofIssue(issue('groups[Hall [2]]', 'voltage'))?.key,
      'group/Hall [2]/voltage',
    );
    expect(
      FieldRef.ofIssue(issue('segments[3]', 'speed'))?.key,
      'item/segments/3/speed',
    );
    expect(FieldRef.ofIssue(issue('project', null)), isNull);
    expect(issue('project', null).severity, isNot(IssueSeverity.$unknown));
    expect(
      Issue.fromJson({
        'severity': 'info',
        'code': 'x',
        'message': 'm',
        'scope': 'project',
      }).severity,
      IssueSeverity.info,
    );
  });

  test('values compare as numbers, codes as text', () {
    expect(sameValue(3, '3.0'), isTrue);
    expect(sameValue('70', '70.0'), isTrue);
    expect(sameValue(0.5, '0.50'), isTrue);
    expect(sameValue('05', '5'), isFalse);
    expect(sameValue('05', 5), isFalse);
    expect(sameValue('05', '05'), isTrue);
    expect(sameValue(true, 'true'), isTrue);
  });

  test('new configurations start with min_rows, within max_rows', () {
    int rows(Map<String, Object?> t) =>
        CfgItemTable({'name': 't', ...t}).initialRows;
    expect(rows({}), 1);
    expect(rows({'min_rows': 3}), 3);
    expect(rows({'max_rows': 0}), 0);
    expect(rows({'min_rows': 0}), 0);
    expect(rows({'min_rows': 50}), 20);
  });

  test('converts units within a dimension', () {
    expect(convertUnit('400', 'voltage', 'V', 'kV'), '0.4');
    expect(convertUnit('1.5', 'length', 'm', 'mm'), '1500');
    expect(convertUnit('1', 'speed', 'm/s', 'm/min'), '60');
    expect(convertUnit('30', 'speed', 'm/min', 'm/s'), '0.5');
    expect(convertUnit('3', 'speed', 'm/s', 'km/h'), '10.8');
    expect(convertUnit('7', null, 'x', 'y'), '7');
  });

  group('RunnerNotifier', () {
    late FakeHttp http;
    late ProviderContainer container;
    final evaluations = <Object?>[];

    setUp(() {
      RunnerNotifier.debounce = const Duration(milliseconds: 20);
      evaluations.clear();
      final seed = jsonDecode(
        File('../seed/configurators/conveyor_line.json').readAsStringSync(),
      ) as Map<String, Object?>;
      http = FakeHttp({
        'GET /api/v1/configurator/configurations/cfg1': (_) => {
          'id': 'cfg1',
          'model_id': 'm1',
          'model_code': 'CONVEYOR-LINE',
          'model_name': 'Conveyor line',
          'revision_id': 'rev1',
          'revision': 1,
          'revision_status': 'active',
          'customer_id': 'c1',
          'customer_name': 'Alpha',
          'name': '',
          'inputs': <String, Object?>{},
          'created_at': '2026-11-08T10:00:00Z',
          'updated_at': '2026-11-08T10:00:00Z',
        },
        'GET /api/v1/configurator/revisions/rev1': (_) => {
          'id': 'rev1',
          'model_id': 'm1',
          'model_code': 'CONVEYOR-LINE',
          'model_name': 'Conveyor line',
          'revision': 1,
          'status': 'active',
          'notes': '',
          'definition': seed['definition'],
          'errors': <Object?>[],
          'created_at': '2026-11-08T10:00:00Z',
          'updated_at': '2026-11-08T10:00:00Z',
        },
        'POST /api/v1/configurator/revisions/rev1/evaluate': (body) {
          evaluations.add(body);
          return _evaluation(
            rows: [
              {
                'index': 1,
                'group': 'Hall 1',
                'label': 'Hall 1 / segment 1',
                'values': [
                  _vr(
                    'motor_code',
                    'MOT-110',
                    source: 'calculated',
                    kind: 'computed',
                  ),
                ],
              },
            ],
          ).toJson();
        },
        'PUT /api/v1/configurator/configurations/cfg1': (body) => {
          ...(http.routes['GET /api/v1/configurator/configurations/cfg1']!(null)
              as Map),
          'inputs': (body as Map)['inputs'],
        },
      });
      container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      );
    });

    tearDown(() => container.dispose());

    Future<RunnerNotifier> loaded() async {
      final sub = container.listen(runnerProvider('cfg1'), (_, _) {});
      addTearDown(sub.close);
      final n = container.read(runnerProvider('cfg1').notifier);
      for (
        var i = 0;
        i < 50 && container.read(runnerProvider('cfg1')).loading;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return n;
    }

    test('loads, starts with the required rows and evaluates once', () async {
      await loaded();
      final s = container.read(runnerProvider('cfg1'));
      expect(s.definition?.name, 'Conveyor line');
      expect(s.inputs.rows('segments'), hasLength(1));
      expect(s.dirty, isTrue);
      expect(evaluations, hasLength(1));
      expect(s.evaluation, isNotNull);
    });

    test(
      'debounces changes into one evaluation with the backend input shape',
      () async {
        final n = await loaded();
        evaluations.clear();
        n.setValue(const FieldRef.project('voltage'), '230');
        n.setValue(const FieldRef.item('segments', 0, 'length_m'), '12');
        n.setValue(const FieldRef.item('segments', 0, 'load_kg'), '300');
        expect(
          container.read(runnerProvider('cfg1')).inputs.project['voltage'],
          '230',
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(evaluations, hasLength(1));
        n.pin(const FieldRef.item('segments', 0, 'motor_code'), 'MOT-220');
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(evaluations, hasLength(2));
        expect(evaluations.last, {
          'project': {'voltage': '230'},
          'groups': <String, Object?>{},
          'items': {
            'segments': [
              {'length_m': '12', 'load_kg': '300'},
            ],
          },
          'pins': [
            {
              'name': 'motor_code',
              'table': 'segments',
              'row': 0,
              'value': 'MOT-220',
              'calculated': 'MOT-110',
            },
          ],
        });
        // Picking the calculated value again removes the pin.
        n.pin(const FieldRef.item('segments', 0, 'motor_code'), 'MOT-110');
        expect(container.read(runnerProvider('cfg1')).inputs.pins, isEmpty);
      },
    );

    test('prices lines by their product ids, in the app language', () async {
      Map<String, Object?> line(String code, String? id, [List<Object?>? c]) =>
          {
            'code': code,
            'product_id': ?id,
            'product_name': ?(id == null ? null : 'Name $code'),
            'quantity': '1',
            'rule': 'r',
            'percent_of_parent': ?(c == null ? '20' : null),
            'children': c ?? <Object?>[],
            'trace': {'rule': 'r', 'rule_path': r'$.outputs[0]', 'sources': []},
          };
      http.routes['POST /api/v1/configurator/revisions/rev1/evaluate'] = (_) =>
          _evaluation(
            lines: [
              line('MOT-110', 'p-mot', [line('COAT-PROT', 'p-coat')]),
              line('UNKNOWN', null, []),
            ],
          ).toJson();
      http.routes['POST /api/v1/pricing/preview'] = (_) => {
        'price_zone_code': 'Z2',
        'customer_discount_percent': '0',
        'quote_date': '2026-11-08',
        'price_date': '2026-11-08',
        'unconfirmed_lines': 0,
        'warnings': <Object?>[],
        'suggestions': <Object?>[],
        'lines': <Object?>[],
        'vat_groups': <Object?>[],
        'subtotal': '0',
        'vat_total': '0',
        'total': '0',
      };
      container.read(runnerProvider('cfg1').notifier).language = 'nl';
      await loaded();
      final i = http.requests.indexOf(
        'POST /api/v1/configurator/revisions/rev1/evaluate',
      );
      expect(http.queries[i]['language'], 'nl');
      expect(http.requests.where((r) => r.contains('/products')), isEmpty);
      final body = http.bodies['POST /api/v1/pricing/preview'] as Map;
      expect(body['lines'], [
        {'product_id': 'p-mot', 'quantity': '1'},
        {
          'product_id': 'p-coat',
          'quantity': '1',
          'parent_position': 1,
          'percent_of_parent': '20',
        },
      ]);
      expect(container.read(runnerProvider('cfg1')).pricedPositions, {
        '0': 0,
        '0.0': 1,
      });
    });

    test('saves the inputs', () async {
      final n = await loaded();
      n.setName('Line A');
      await n.save();
      final body =
          http.bodies['PUT /api/v1/configurator/configurations/cfg1'] as Map;
      expect(body['name'], 'Line A');
      expect(body['customer_id'], 'c1');
      expect((body['inputs'] as Map)['items'], {
        'segments': [<String, Object?>{}],
      });
      expect(container.read(runnerProvider('cfg1')).dirty, isFalse);
    });
  });

  // -------------------------------------------------------------------------------------------
  // Form renderer
  // -------------------------------------------------------------------------------------------
  group('form renderer', () {
    testWidgets('renders each field type and stores typed values', (
      tester,
    ) async {
      final actions = await _pumpProjectForm(
        tester,
        _evaluation(project: _projectValues),
      );

      // Section title, required/visible fields; the hidden one is not shown.
      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Coating class'), findsNothing);
      expect(find.text('Helper'), findsNothing);

      // Number: the default shows as a hint, typing stores the value in the field's unit.
      expect(find.widgetWithText(TextField, '400'), findsOneWidget);
      await tester.enterText(_field('Voltage'), '230');
      expect(actions.inputs.project['voltage'], '230');
      // Decimal comma is accepted.
      await tester.enterText(_field('Voltage'), '230,5');
      expect(actions.inputs.project['voltage'], '230.5');
      // Garbage is refused and flagged.
      await tester.enterText(_field('Voltage'), '23x');
      await tester.pump();
      expect(actions.inputs.project['voltage'], '230.5');
      expect(find.text('Not a valid number'), findsOneWidget);

      // Integer.
      await tester.enterText(_field('Count'), '4');
      expect(actions.inputs.project['count'], 4);

      // Text.
      await tester.enterText(_field('Note'), 'hello');
      expect(actions.inputs.project['note'], 'hello');

      // Boolean.
      await tester.tap(find.text('Coating'));
      expect(actions.inputs.project['coating'], true);

      // Choice: options from the evaluation, labels from the definition.
      await tester.tap(find.text('Three phase'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Single phase').last);
      await tester.pumpAndSettle();
      expect(actions.inputs.project['phases'], 1);

      // Product: suggestions are the evaluation's options.
      await tester.tap(_field('Extra product'));
      await tester.enterText(_field('Extra product'), 'ACC');
      await tester.pumpAndSettle();
      expect(find.text('ACC-2'), findsOneWidget);
      await tester.tap(find.text('ACC-2'));
      await tester.pumpAndSettle();
      expect(actions.inputs.project['extra'], 'ACC-2');
    });

    testWidgets('number input in another display unit is converted', (
      tester,
    ) async {
      final actions = await _pumpProjectForm(
        tester,
        _evaluation(project: _projectValues),
        const RunnerInputs(project: {'voltage': '400'}),
      );
      await tester.tap(find.text('V').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('kV').last);
      await tester.pumpAndSettle();
      expect(actions.units['voltage'], 'kV');
      expect(find.widgetWithText(TextField, '0.4'), findsOneWidget);
      await tester.enterText(_field('Voltage'), '0.23');
      expect(actions.inputs.project['voltage'], '230');
    });

    testWidgets('visibility and enabled state come from the evaluation', (
      tester,
    ) async {
      final values = [
        for (final v in _projectValues)
          if (v['name'] == 'coating_class')
            _vr('coating_class', 'C4', source: 'default', options: ['C3', 'C4'])
          else if (v['name'] == 'note')
            _vr('note', null, source: 'empty', enabled: false)
          else
            v,
      ];
      await _pumpProjectForm(tester, _evaluation(project: values));
      expect(find.text('Coating class'), findsOneWidget);
      final note = tester.widget<TextField>(_field('Note'));
      expect(note.enabled, isFalse);
    });

    testWidgets('calculated values are italic with a marker', (tester) async {
      await _pumpProjectForm(tester, _evaluation(project: _projectValues));
      final total = tester.widget<Text>(find.text('12.5 m'));
      expect(total.style?.fontStyle, FontStyle.italic);
      expect(total.style?.fontWeight, isNot(FontWeight.bold));
      expect(find.byTooltip('Calculated'), findsWidgets);
    });

    testWidgets('overridable values can be pinned, shown bold and reset', (
      tester,
    ) async {
      final actions = await _pumpProjectForm(
        tester,
        _evaluation(project: _projectValues),
      );
      await tester.tap(find.text('MOT-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('MOT-2').last);
      await tester.pumpAndSettle();
      expect(actions.pins['project/motor'], 'MOT-2');

      // As the server reports it once pinned.
      final pinned = [
        for (final v in _projectValues)
          if (v['name'] == 'motor')
            _vr(
              'motor',
              'MOT-2',
              source: 'pinned',
              kind: 'computed',
              calculated: 'MOT-1',
              options: ['MOT-1', 'MOT-2'],
            )
          else
            v,
      ];
      await _pumpProjectForm(tester, _evaluation(project: pinned));
      final shown = tester.widget<Text>(
        find
            .descendant(
              of: find.byType(DropdownButton<int>),
              matching: find.text('MOT-2'),
            )
            .first,
      );
      expect(shown.style?.fontWeight, FontWeight.bold);
      expect(find.byTooltip('Your own value (pinned)'), findsOneWidget);
      expect(find.byTooltip('Reset to calculated (MOT-1)'), findsOneWidget);
    });

    testWidgets('reset to calculated unpins', (tester) async {
      final stale = [
        for (final v in _projectValues)
          if (v['name'] == 'motor')
            _vr(
              'motor',
              'MOT-2',
              source: 'stale',
              kind: 'computed',
              calculated: 'MOT-3',
              options: ['MOT-1', 'MOT-2', 'MOT-3'],
            )
          else
            v,
      ];
      final actions = await _pumpProjectForm(
        tester,
        _evaluation(project: stale),
        RunnerInputs(
          pins: [const FieldRef.project('motor').pin('MOT-2', 'MOT-1')],
        ),
      );
      // Stale: a warning with what the calculation gives now.
      expect(find.text('The calculation now gives MOT-3'), findsOneWidget);
      await tester.tap(find.byTooltip('Reset to calculated (MOT-3)'));
      await tester.pump();
      expect(actions.unpinned, ['project/motor']);
      expect(actions.inputs.pins, isEmpty);
    });
  });

  // -------------------------------------------------------------------------------------------
  // Item grid
  // -------------------------------------------------------------------------------------------
  group('item grid', () {
    Future<_FakeActions> pumpGrid(
      WidgetTester tester,
      RunnerInputs inputs,
    ) async {
      final actions = _FakeActions(inputs);
      final def = CfgDefinition(_definition);
      await _pump(
        tester,
        _Harness(
          actions: actions,
          evaluation: _evaluation(),
          build: (view) => ItemGrid(view: view, table: def.itemTables.single),
        ),
      );
      return actions;
    }

    final twoHalls = const RunnerInputs()
        .addRow('segments', {'hall': 'A', 'length_m': '10'})
        .addRow('segments', {'hall': 'B', 'length_m': '20'})
        .addRow('segments', {'hall': 'A', 'length_m': '30'});

    testWidgets('groups rows by the group field', (tester) async {
      await pumpGrid(tester, twoHalls);
      expect(find.byKey(const ValueKey('group-segments-A')), findsOneWidget);
      expect(find.byKey(const ValueKey('group-segments-B')), findsOneWidget);
      // Rows 1 and 3 (hall A) come before row 2 (hall B).
      final y1 = tester
          .getTopLeft(find.byKey(const ValueKey('row-segments-0')))
          .dy;
      final y2 = tester
          .getTopLeft(find.byKey(const ValueKey('row-segments-1')))
          .dy;
      final y3 = tester
          .getTopLeft(find.byKey(const ValueKey('row-segments-2')))
          .dy;
      expect(y1 < y3 && y3 < y2, isTrue);
      // Computed columns are shown (read-only or pinnable).
      expect(find.textContaining('Motor'), findsWidgets);
    });

    testWidgets('adds, duplicates and deletes rows', (tester) async {
      final actions = await pumpGrid(tester, twoHalls);
      await tester.tap(find.text('Add Segment'));
      await tester.pump();
      expect(actions.inputs.rows('segments'), hasLength(4));
      // A new row joins the last row's group.
      expect(actions.inputs.rows('segments').last['hall'], 'A');

      // Add to group B from its header.
      await tester.tap(find.byTooltip('Add a row to B'));
      await tester.pump();
      expect(actions.inputs.rows('segments').last, {'hall': 'B'});

      await tester.tap(find.byTooltip('Duplicate row').at(0));
      await tester.pump();
      expect(
        [for (final r in actions.inputs.rows('segments')) r['length_m']],
        ['10', '10', '20', '30', null, null],
      );

      await tester.tap(find.byTooltip('Delete row').first);
      await tester.pump();
      expect(
        [for (final r in actions.inputs.rows('segments')) r['length_m']],
        ['10', '20', '30', null, null],
      );
    });

    testWidgets('edits a cell and bulk-edits a column from its header', (
      tester,
    ) async {
      final actions = await pumpGrid(tester, twoHalls);
      await tester.enterText(find.widgetWithText(TextField, '20'), '25');
      expect(actions.inputs.rows('segments')[1]['length_m'], '25');

      await tester.tap(find.byKey(const ValueKey('bulk-segments-length_m')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set for all rows…'));
      await tester.pumpAndSettle();
      expect(find.text('Length for all rows'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '5',
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        [for (final r in actions.inputs.rows('segments')) r['length_m']],
        ['5', '5', '5'],
      );

      // Booleans too.
      await tester.tap(find.byKey(const ValueKey('bulk-segments-stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set for all rows…'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Checkbox),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(
        actions.inputs.rows('segments').every((r) => r['stop'] == true),
        isTrue,
      );
    });

    testWidgets('shows the column in the chosen display unit', (tester) async {
      final actions = await pumpGrid(tester, twoHalls);
      await tester.tap(find.byKey(const ValueKey('bulk-segments-length_m')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, 'mm'));
      await tester.pumpAndSettle();
      expect(actions.units['segments.length_m'], 'mm');
      expect(find.widgetWithText(TextField, '20000'), findsOneWidget);
      expect(find.text('Length (mm)'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------------------------
  // Panels
  // -------------------------------------------------------------------------------------------
  testWidgets('issues are grouped by severity and focus their field', (
    tester,
  ) async {
    Issue? tapped;
    final issues = [
      Issue.fromJson({
        'severity': 'warning',
        'code': 'w',
        'message': 'Low voltage',
        'scope': 'groups[A]',
        'field': 'voltage',
      }),
      Issue.fromJson({
        'severity': 'error',
        'code': 'required',
        'message': 'Length is required',
        'scope': 'segments[0]',
        'field': 'length_m',
      }),
      Issue.fromJson({
        'severity': 'info',
        'code': 'i',
        'message': 'Fast belt',
        'scope': 'project',
      }),
    ];
    await _pump(
      tester,
      SizedBox(
        height: 500,
        child: IssuesPanel(issues: issues, onTap: (i) => tapped = i),
      ),
    );
    expect(find.text('Errors (1)'), findsOneWidget);
    expect(find.text('Warnings (1)'), findsOneWidget);
    expect(find.text('Information (1)'), findsOneWidget);
    final errorsY = tester.getTopLeft(find.text('Errors (1)')).dy;
    final warningsY = tester.getTopLeft(find.text('Warnings (1)')).dy;
    expect(errorsY < warningsY, isTrue);
    await tester.tap(find.text('Length is required'));
    expect(FieldRef.ofIssue(tapped!)?.key, 'item/segments/0/length_m');
  });

  testWidgets(
    'lines show sections, nested options and the trace of a selection',
    (tester) async {
      List<int>? selected;
      Map<String, Object?> line(
        String code, {
        List<Object?> children = const [],
        String? section,
        String? pct,
        String? productName,
      }) => {
        'code': code,
        if (productName != null) 'product_id': 'id-$code',
        'product_name': ?productName,
        'quantity': '2',
        'rule': 'motor',
        'section': ?section,
        'percent_of_parent': ?pct,
        'children': children,
        'trace': {
          'rule': 'motor',
          'rule_path': r'$.outputs[1]',
          'sources': [
            {
              'scope': 'segments[0]',
              'label': 'Hall 1 / segment 1',
              'values': {'motor_code': 'MOT-110'},
            },
          ],
        },
      };
      final e = _evaluation(
        lines: [
          line(
            'MOT-110',
            section: 'Hall 1',
            productName: 'Motor 1.1 kW',
            children: [line('COAT-PROT', pct: '20', productName: 'Protection')],
          ),
          line('INSTALL', section: 'Installation'),
        ],
      );
      await _pump(
        tester,
        SizedBox(
          height: 500,
          child: LinesPanel(lines: e.lines, onSelect: (p) => selected = p),
        ),
      );
      expect(find.text('Hall 1'), findsOneWidget);
      expect(find.text('Installation'), findsOneWidget);
      expect(find.text('20 %'), findsOneWidget);
      expect(find.text('Choose a customer to see prices.'), findsOneWidget);
      // Product names come with the evaluation; a code without a product is flagged.
      expect(find.text('MOT-110 · Motor 1.1 kW'), findsOneWidget);
      expect(find.text('Not in the product catalogue'), findsOneWidget);
      await tester.tap(find.text('COAT-PROT · Protection'));
      expect(selected, [0, 0]);

      await _pump(
        tester,
        SizedBox(height: 500, child: WhyPanel(line: lineAt(e.lines, [0]))),
      );
      expect(find.text('Rule: motor'), findsOneWidget);
      expect(find.text('Hall 1 / segment 1'), findsOneWidget);
      expect(find.text('MOT-110'), findsOneWidget);
    },
  );

  testWidgets('saved configurations show model, revision and quotation', (
    tester,
  ) async {
    final http = FakeHttp({
      'GET /api/v1/configurator/models': (_) => <Object?>[],
      'GET /api/v1/configurator/configurations': (_) => [
        {
          'id': 'cfg1',
          'model_id': 'm1',
          'model_code': 'CONVEYOR-LINE',
          'model_name': 'Conveyor line',
          'name': 'Line A',
          'revision': 1,
          'newer_revision': 2,
          'customer_name': 'Alpha',
          'quotation_id': 'q1',
          'quotation_number': 'Q2026-00007',
          'updated_at': '2026-11-08T10:00:00Z',
        },
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [dioProvider.overrideWithValue(fakeDio(http))],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: ConfiguratorPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Line A · Conveyor line'), findsOneWidget);
    expect(
      find.textContaining('revision 1 · revision 2 available · Q2026-00007'),
      findsOneWidget,
    );
  });
}
