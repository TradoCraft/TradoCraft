import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/reports/report_builder_page.dart';
import 'package:tradocraft_app/features/reports/report_draft.dart';
import 'package:tradocraft_app/features/reports/report_result_view.dart';
import 'package:tradocraft_app/features/reports/report_screen.dart';
import 'package:tradocraft_app/features/reports/reports_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/csv_transfer.dart';

import 'fake_http.dart';

const _writer = ['reports.read', 'reports.write'];
const _reader = ['reports.read'];

Map<String, Object?> _field(
  String name,
  String label,
  String type, {
  bool countOnly = false,
}) => {'name': name, 'label': label, 'type': type, 'count_only': countOnly};

Map<String, Object?> _catalog() => {
  'objects': [
    {
      'name': 'customer',
      'label': 'Customers',
      'fields': [
        _field(
          'customer.records',
          'Number of records',
          'text',
          countOnly: true,
        ),
        _field('customer.code', 'Code', 'text'),
        _field('customer.name', 'Name', 'text'),
      ],
    },
    {
      'name': 'quotation',
      'label': 'Quotations',
      'fields': [
        _field(
          'quotation.records',
          'Number of records',
          'text',
          countOnly: true,
        ),
        _field('quotation.number', 'Number', 'text'),
        _field('quotation.status', 'Status', 'text'),
        _field('quotation.quote_date', 'Quote date', 'date'),
        _field('quotation.total', 'Total', 'number'),
      ],
    },
  ],
  'links': [
    {'a': 'customer', 'b': 'quotation'},
  ],
};

Map<String, Object?> _definition() => {
  'object': 'quotation',
  'columns': [
    {'field': 'quotation.total', 'summary': 'sum'},
  ],
  'filters': [
    {'field': 'quotation.total', 'op': 'gte', 'value': 100},
  ],
  'filter_logic': 'and',
  'group_by': [
    {'field': 'quotation.status'},
  ],
  'sort': [
    {'column': 'quotation.total:sum', 'dir': 'desc'},
  ],
  'chart': {'kind': 'bar', 'x': 'quotation.status', 'y': 'quotation.total:sum'},
};

Map<String, Object?> _report({
  String id = 'r1',
  String name = 'Total by status',
  bool mine = true,
  bool shared = false,
  Map<String, Object?>? definition,
}) => {
  'id': id,
  'name': name,
  'description': 'Quotes of 2027',
  'object': 'quotation',
  'definition': definition ?? _definition(),
  'shared': shared,
  'owner_id': mine ? 'u1' : 'u2',
  'owner_name': mine ? 'Sales User' : 'Colleague',
  'mine': mine,
  'created_at': '2027-01-01T09:00:00Z',
  'updated_at': '2027-01-01T09:00:00Z',
};

Map<String, Object?> _result({
  List<List<Object?>>? rows,
  int? total,
  String chart = 'bar',
  String asOf = '2027-01-15',
}) => {
  'as_of': asOf,
  'columns': [
    {
      'key': 'quotation.status',
      'label': 'Status',
      'type': 'text',
      'kind': 'group',
    },
    {
      'key': 'quotation.total:sum',
      'label': 'Sum of Total',
      'type': 'number',
      'kind': 'summary',
    },
  ],
  'rows':
      rows ??
      [
        ['accepted', 750.0],
        ['draft', 250.0],
      ],
  'total': total ?? 2,
  'totals': [null, 1000.0],
  'chart': {'kind': chart, 'x': 'quotation.status', 'y': 'quotation.total:sum'},
};

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http,
  Widget home, {
  CsvSaver? saver,
}) async {
  tester.view.physicalSize = const Size(1400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      GoRoute(path: '/reports', builder: (_, _) => const Text('LIST PAGE')),
      GoRoute(path: '/reports/:id', builder: (_, _) => const Text('VIEW PAGE')),
      GoRoute(
        path: '/reports/:id/edit',
        builder: (_, _) => const Text('EDIT PAGE'),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        if (saver != null) csvSaverProvider.overrideWithValue(saver),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('draft', () {
    late ReportCatalog catalog;
    setUp(() => catalog = ReportCatalog.fromJson(_catalog()));

    test('custom column headings survive editing', () {
      final def = {
        ..._definition(),
        'columns': [
          {'field': 'quotation.total', 'summary': 'sum', 'label': 'Revenue'},
        ],
      };
      final report = SavedReport.fromJson({..._report(), 'definition': def});
      final back = jsonDecode(
        jsonEncode(ReportDraft.from(report).toDefinition(catalog)),
      ) as Map<String, dynamic>;
      expect((back['columns'] as List).first['label'], 'Revenue');
    });

    test('list values with commas round-trip and dates allow "is one of"', () {
      expect(operatorsFor(ReportFieldType.date), contains(ReportOp.valueIn));
      expect(
        filterValue(ReportFieldType.text, ReportOp.valueIn, 'a, "b, c", d'),
        ['a', 'b, c', 'd'],
      );
      final def = {
        ..._definition(),
        'filters': [
          {
            'field': 'quotation.status',
            'op': 'in',
            'value': ['x, y', 'z'],
          },
        ],
      };
      final d = ReportDraft.from(
        SavedReport.fromJson({..._report(), 'definition': def}),
      );
      final back = jsonDecode(
        jsonEncode(d.toDefinition(catalog)),
      ) as Map<String, dynamic>;
      expect((back['filters'] as List).first['value'], ['x, y', 'z']);
    });

    test('an empty boolean filter value is true, as the form shows', () {
      expect(filterValue(ReportFieldType.valueBool, ReportOp.eq, ''), true);
      expect(
        filterValue(ReportFieldType.valueBool, ReportOp.eq, 'false'),
        false,
      );
    });

    test('only counts and numeric summaries can be charted', () {
      final d = ReportDraft(object: 'quotation')
        ..columns.addAll([
          DraftColumn('quotation.quote_date', ReportSummary.max),
          DraftColumn('quotation.total', ReportSummary.sum),
          DraftColumn('quotation.number', ReportSummary.count),
        ]);
      expect(d.summaryKeys(catalog).map((k) => k.key), [
        'quotation.total:sum',
        'quotation.number:count',
      ]);
    });

    test('a stored report goes through the form and back unchanged', () {
      final report = SavedReport.fromJson(_report());
      final back = jsonDecode(
        jsonEncode(ReportDraft.from(report).toDefinition(catalog)),
      ) as Map<String, dynamic>;
      expect(back['object'], 'quotation');
      expect(back['columns'], [
        {'field': 'quotation.total', 'summary': 'sum'},
      ]);
      expect(back['group_by'], [
        {'field': 'quotation.status'},
      ]);
      expect(back['filters'], [
        {'field': 'quotation.total', 'op': 'gte', 'value': 100},
      ]);
      expect(back['sort'], [
        {'column': 'quotation.total:sum', 'dir': 'desc'},
      ]);
      expect(back['chart'], {
        'kind': 'bar',
        'x': 'quotation.status',
        'y': 'quotation.total:sum',
      });
      expect(back['filter_logic'], 'and');
      expect(back.containsKey('joins'), isFalse);
    });

    group('relative date filters', () {
      Map<String, Object?> defWith(Object? value, {String op = 'gte'}) => {
        ..._definition(),
        'filters': [
          {'field': 'quotation.quote_date', 'op': op, 'value': value},
        ],
      };

      Object? bodyOf(ReportDraft d) =>
          (jsonDecode(jsonEncode(d.toDefinition(catalog)))
              as Map<String, dynamic>)['filters'];

      test('the draft serializes the exact request body', () {
        final d = ReportDraft(object: 'quotation')
          ..filters.add(
            DraftFilter('quotation.quote_date', ReportOp.gte)
              ..relative = 'last_month',
          )
          ..filters.add(
            DraftFilter('quotation.quote_date', ReportOp.eq)
              ..relative = 'last_n_days'
              ..days = ' 30 ',
          )
          ..filters.add(
            DraftFilter('quotation.quote_date', ReportOp.lt)
              ..relative = 'next_n_days'
              ..days = '3660',
          );
        expect(bodyOf(d), [
          {
            'field': 'quotation.quote_date',
            'op': 'gte',
            'value': {'relative': 'last_month'},
          },
          {
            'field': 'quotation.quote_date',
            'op': 'eq',
            'value': {'relative': 'last_n_days', 'n': 30},
          },
          {
            'field': 'quotation.quote_date',
            'op': 'lt',
            'value': {'relative': 'next_n_days', 'n': 3660},
          },
        ]);
      });

      test('a stored relative filter loads and goes back unchanged', () {
        for (final value in <Map<String, Object?>>[
          {'relative': 'this_quarter'},
          {'relative': 'last_n_days', 'n': 7},
          {'relative': 'next_n_days', 'n': 14},
        ]) {
          final report = SavedReport.fromJson(
            _report(definition: defWith(value)),
          );
          final d = ReportDraft.from(report);
          expect(d.filters.single.relative, value['relative']);
          expect(d.filters.single.value, '');
          expect(bodyOf(d), [
            {'field': 'quotation.quote_date', 'op': 'gte', 'value': value},
          ]);
        }
      });

      test('a fixed date is unaffected', () {
        final d = ReportDraft.from(
          SavedReport.fromJson(_report(definition: defWith('2027-01-31'))),
        );
        expect(d.filters.single.relative, isNull);
        expect(bodyOf(d), [
          {'field': 'quotation.quote_date', 'op': 'gte', 'value': '2027-01-31'},
        ]);
      });

      test('relative is ignored for operators and fields that refuse it', () {
        final isNull = DraftFilter('quotation.quote_date', ReportOp.isNull)
          ..relative = 'today';
        final other = DraftFilter('quotation.total', ReportOp.gte, '5')
          ..relative = 'today';
        final d = ReportDraft(object: 'quotation')
          ..filters.addAll([isNull, other]);
        expect(bodyOf(d), [
          {'field': 'quotation.quote_date', 'op': 'is_null'},
          {'field': 'quotation.total', 'op': 'gte', 'value': 5},
        ]);
        expect(relativeAllowedFor(ReportOp.valueIn), isFalse);
        expect(relativeAllowedFor(ReportOp.notNull), isFalse);
        expect(relativeAllowedFor(ReportOp.eq), isTrue);
      });

      test('the number of days must be a whole number from 1 to 3660', () {
        DraftFilter withDays(String n) =>
            DraftFilter('quotation.quote_date', ReportOp.gte)
              ..relative = 'last_n_days'
              ..days = n;
        for (final ok in ['1', '30', '3660']) {
          expect(withDays(ok).relativeInvalid, isFalse, reason: ok);
        }
        for (final bad in ['', '0', '3661', '-5', '1.5', 'abc']) {
          expect(withDays(bad).relativeInvalid, isTrue, reason: bad);
        }
        // Tokens without a number never need one.
        expect(
          (DraftFilter('quotation.quote_date', ReportOp.gte)
                ..relative = 'today'
                ..days = '')
              .relativeInvalid,
          isFalse,
        );
        expect(
          (ReportDraft(
            object: 'quotation',
          )..filters.add(withDays('0'))).hasInvalidRelative,
          isTrue,
        );
      });
    });

    test('a chart or sort that points at something gone is dropped', () {
      // Without the grouping the chart has no categories left; the sort still names a column.
      final d = ReportDraft.from(SavedReport.fromJson(_report()))
        ..groups.clear();
      var out = jsonDecode(
        jsonEncode(d.toDefinition(catalog)),
      ) as Map<String, dynamic>;
      expect(out.containsKey('chart'), isFalse);
      expect(out['sort'], hasLength(1));
      // Without the column the sort has nothing to sort on either.
      d.columns.clear();
      out = jsonDecode(
        jsonEncode(d.toDefinition(catalog)),
      ) as Map<String, dynamic>;
      expect(out['sort'], isEmpty);
    });

    test('output keys list groupings first and name buckets and summaries', () {
      final d = ReportDraft(object: 'quotation')
        ..groups.add(DraftGroup('quotation.quote_date', ReportBucket.month))
        ..columns.add(DraftColumn('quotation.total', ReportSummary.avg));
      expect(d.outputKeys(catalog).map((k) => k.key), [
        'quotation.quote_date:month',
        'quotation.total:avg',
      ]);
      expect(d.groupKeys(catalog).single.key, 'quotation.quote_date:month');
      expect(d.summaryKeys(catalog).single.key, 'quotation.total:avg');
    });

    test('filter values are typed from what was typed', () {
      expect(filterValue(ReportFieldType.number, ReportOp.gte, '12,5'), '12.5');
      expect(filterValue(ReportFieldType.number, ReportOp.gte, '12.5'), 12.5);
      expect(filterValue(ReportFieldType.number, ReportOp.eq, '7'), 7);
      expect(filterValue(ReportFieldType.text, ReportOp.eq, ' abc '), 'abc');
      expect(filterValue(ReportFieldType.text, ReportOp.valueIn, 'a, b ,,c'), [
        'a',
        'b',
        'c',
      ]);
      expect(filterValue(ReportFieldType.valueBool, ReportOp.eq, 'true'), true);
      expect(
        filterValue(ReportFieldType.valueBool, ReportOp.eq, 'false'),
        false,
      );
      expect(
        filterValue(ReportFieldType.date, ReportOp.lt, '2027-01-31'),
        '2027-01-31',
      );
      expect(filterValue(ReportFieldType.text, ReportOp.isNull, 'x'), isNull);
    });

    test('operators and summaries follow the field type', () {
      expect(operatorsFor(ReportFieldType.number), contains(ReportOp.gte));
      expect(operatorsFor(ReportFieldType.text), isNot(contains(ReportOp.gte)));
      expect(operatorsFor(ReportFieldType.text), contains(ReportOp.contains));
      expect(
        operatorsFor(ReportFieldType.valueBool),
        isNot(contains(ReportOp.contains)),
      );
      final total = catalog.field('quotation.total')!;
      final number = catalog.field('quotation.number')!;
      final records = catalog.field('quotation.records')!;
      expect(summariesFor(total, grouped: false), contains(null));
      expect(summariesFor(total, grouped: true), isNot(contains(null)));
      expect(summariesFor(total, grouped: true), contains(ReportSummary.sum));
      expect(summariesFor(number, grouped: true), [ReportSummary.count]);
      expect(summariesFor(records, grouped: false), [ReportSummary.count]);
    });

    test('catalog lookups find fields and joinable objects', () {
      expect(catalog.field('quotation.total')?.label, 'Total');
      expect(catalog.field('nope.x'), isNull);
      expect(catalog.joinable(['customer']).map((o) => o.name), ['quotation']);
      expect(catalog.joinable(['customer', 'quotation']), isEmpty);
      expect(
        catalog.fieldsOf(['customer', 'quotation']).first.name,
        'customer.records',
      );
    });
  });

  group('helpers', () {
    test('file names are letters and digits', () {
      expect(reportFileBase('Total by Status / 2027'), 'total-by-status-2027');
      expect(reportFileBase('  --  '), 'report');
    });

    test('an export error carries the server message from the body bytes', () {
      DioException error(Object? data) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: data,
        ),
      );
      final body = utf8.encode(
        jsonEncode({'error': 'validation', 'message': 'too many rows'}),
      );
      expect(exportErrorMessage(error(body)), 'too many rows');
      expect(exportErrorMessage(error(<int>[1, 2, 3])), 'Server error 422.');
    });
  });

  group('saved reports list', () {
    FakeHttp http(List<String> perms, List<Object?> reports) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/custom-reports': (_) => reports,
    });

    testWidgets(
      'lists reports with who owns them and whether they are shared',
      (tester) async {
        await _pump(
          tester,
          http(_writer, [
            _report(),
            _report(id: 'r2', name: 'Open orders', mine: false, shared: true),
          ]),
          const SavedReportsPage(),
        );
        expect(find.text('Total by status'), findsOneWidget);
        expect(find.text('Open orders'), findsOneWidget);
        expect(find.text('Private'), findsOneWidget);
        expect(find.text('Shared'), findsOneWidget);
        expect(find.textContaining('By Colleague'), findsOneWidget);
        expect(find.byKey(const ValueKey('new-report')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('report-r2')));
        await tester.pumpAndSettle();
        expect(find.text('VIEW PAGE'), findsOneWidget);
      },
    );

    testWidgets('only people who may write see the new report button', (
      tester,
    ) async {
      await _pump(tester, http(_reader, [_report()]), const SavedReportsPage());
      expect(find.text('Total by status'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-report')), findsNothing);
    });

    testWidgets('an empty list explains itself', (tester) async {
      await _pump(tester, http(_writer, []), const SavedReportsPage());
      expect(find.textContaining('No reports yet'), findsOneWidget);
    });
  });

  group('report screen', () {
    FakeHttp http({
      List<String> perms = _writer,
      bool mine = true,
      Object? Function(Object?)? run,
      Map<String, Object? Function(Object?)> extra = const {},
    }) => FakeHttp({
      'GET /api/v1/me': (_) => meJson(perms),
      'GET /api/v1/custom-reports/r1': (_) => _report(mine: mine),
      'GET /api/v1/custom-reports/r1/run': run ?? (_) => _result(),
      ...extra,
    });

    testWidgets('shows the table with totals, and the chart', (tester) async {
      await _pump(tester, http(), const SavedReportScreen(id: 'r1'));
      expect(find.text('Total by status'), findsWidgets);
      expect(find.text('Status'), findsOneWidget);
      expect(find.text('Sum of Total'), findsWidgets);
      expect(find.text('accepted'), findsWidgets);
      // Belgian notation, and a totals line.
      expect(find.text('1.000'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('2 rows'), findsOneWidget);
      expect(find.text('Sum of Total / Status'), findsOneWidget);
    });

    testWidgets('an empty report says so', (tester) async {
      await _pump(
        tester,
        http(run: (_) => _result(rows: [], total: 0)),
        const SavedReportScreen(id: 'r1'),
      );
      expect(find.text('No rows match this report.'), findsOneWidget);
    });

    testWidgets('fetches more rows on request', (tester) async {
      var calls = 0;
      final h = http(
        run: (_) {
          calls++;
          return calls == 1
              ? _result(
                  rows: [
                    for (var i = 0; i < 100; i++) ['s$i', 1.0],
                  ],
                  total: 150,
                  asOf: '2027-01-15',
                )
              : _result(
                  // Past midnight the server would answer for a later day; it must not matter.
                  asOf: '2027-01-16',
                  rows: [
                    for (var i = 100; i < 150; i++) ['s$i', 1.0],
                  ],
                  total: 150,
                );
        },
      );
      await _pump(tester, h, const SavedReportScreen(id: 'r1'));
      expect(find.text('Show more rows'), findsOneWidget);
      // The totals line only appears once everything is loaded.
      expect(find.text('1.000'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Show more rows'),
        500,
        scrollable: find.byType(Scrollable).first,
      );
      // Built is not yet on screen: bring the button fully into view before tapping it.
      await tester.ensureVisible(find.text('Show more rows'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show more rows'));
      await tester.pumpAndSettle();
      expect(find.text('Show more rows'), findsNothing);
      final runs = [
        for (var i = 0; i < h.requests.length; i++)
          if (h.requests[i] == 'GET /api/v1/custom-reports/r1/run')
            h.queries[i],
      ];
      expect(runs.map((q) => q['offset']), [0, 100]);
      expect(runs.map((q) => q['limit']), [100, 100]);
      // The first page had no anchor; page 2 sends the day page 1 resolved against.
      expect(runs.map((q) => q['as_of']), [null, '2027-01-15']);
      expect(find.text('150 rows'), findsOneWidget);
      expect(find.text('1.000'), findsOneWidget);
    });

    testWidgets(
      'exports CSV through the saver, with a file name from the report',
      (tester) async {
        String? name;
        Uint8List? sent;
        final csv = Uint8List.fromList(utf8.encode('Status,Amount\r\n'));
        await _pump(
          tester,
          http(
            extra: {
              'GET /api/v1/custom-reports/r1/export?format=csv&as_of=2027-01-15':
                  (_) => csv,
            },
          ),
          const SavedReportScreen(id: 'r1'),
          saver: (filename, bytes) async {
            name = filename;
            sent = bytes;
            return true;
          },
        );
        await tester.tap(find.byKey(const ValueKey('export-csv')));
        await tester.pumpAndSettle();
        expect(name, 'total-by-status.csv');
        expect(sent, csv);
      },
    );

    testWidgets(
      'exports carry the as_of of the result on screen, CSV and PDF',
      (tester) async {
        final h = http(
          // The table was run on 2027-01-10; the export must not resolve another day.
          run: (_) => _result(asOf: '2027-01-10'),
          extra: {
            'GET /api/v1/custom-reports/r1/export?format=csv&as_of=2027-01-10':
                (_) => Uint8List.fromList(utf8.encode('a\r\n')),
            'GET /api/v1/custom-reports/r1/export?format=pdf&as_of=2027-01-10':
                (_) => Uint8List.fromList(utf8.encode('%PDF')),
          },
        );
        await _pump(tester, h, const SavedReportScreen(id: 'r1'));
        await tester.tap(find.byKey(const ValueKey('export-csv')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('export-pdf')));
        await tester.pumpAndSettle();
        final exports = h.requests.where((r) => r.contains('/export')).toList();
        expect(exports, [
          'GET /api/v1/custom-reports/r1/export?format=csv&as_of=2027-01-10',
          'GET /api/v1/custom-reports/r1/export?format=pdf&as_of=2027-01-10',
        ]);
      },
    );

    test('the export path omits as_of without a result', () {
      expect(
        exportPath('r1', 'csv', null),
        '/api/v1/custom-reports/r1/export?format=csv',
      );
      expect(
        exportPath('r1', 'pdf', DateTime(2027, 1, 5)),
        '/api/v1/custom-reports/r1/export?format=pdf&as_of=2027-01-05',
      );
    });

    testWidgets('shows the server message when an export is refused', (
      tester,
    ) async {
      await _pump(
        tester,
        http(
          extra: {
            'GET /api/v1/custom-reports/r1/export?format=pdf&as_of=2027-01-15':
                (_) => const FakeStatus(422, {
                  'error': 'validation',
                  'message': 'the report has more than 2000 rows',
                }),
          },
        ),
        const SavedReportScreen(id: 'r1'),
      );
      await tester.tap(find.byKey(const ValueKey('export-pdf')));
      await tester.pumpAndSettle();
      expect(find.text('the report has more than 2000 rows'), findsOneWidget);
    });

    testWidgets('the owner can edit and delete; a colleague can only run', (
      tester,
    ) async {
      await _pump(tester, http(mine: false), const SavedReportScreen(id: 'r1'));
      expect(find.byKey(const ValueKey('export-csv')), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-report')), findsNothing);
      expect(find.byKey(const ValueKey('delete-report')), findsNothing);
    });

    testWidgets('an admin may change a colleague\'s report', (tester) async {
      await _pump(
        tester,
        http(mine: false, perms: [..._writer, 'users.admin']),
        const SavedReportScreen(id: 'r1'),
      );
      expect(find.byKey(const ValueKey('edit-report')), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-report')), findsOneWidget);
    });

    testWidgets('a reader cannot edit even their own report', (tester) async {
      await _pump(
        tester,
        http(perms: _reader),
        const SavedReportScreen(id: 'r1'),
      );
      expect(find.byKey(const ValueKey('edit-report')), findsNothing);
    });

    testWidgets('deleting asks first, then goes back to the list', (
      tester,
    ) async {
      final h = http(extra: {'DELETE /api/v1/custom-reports/r1': (_) => null});
      await _pump(tester, h, const SavedReportScreen(id: 'r1'));
      await tester.tap(find.byKey(const ValueKey('delete-report')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this report?'), findsOneWidget);
      expect(h.requests, isNot(contains('DELETE /api/v1/custom-reports/r1')));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(h.requests, isNot(contains('DELETE /api/v1/custom-reports/r1')));

      await tester.tap(find.byKey(const ValueKey('delete-report')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-delete')));
      await tester.pumpAndSettle();
      expect(h.requests, contains('DELETE /api/v1/custom-reports/r1'));
      expect(find.text('LIST PAGE'), findsOneWidget);
    });

    testWidgets('a report that fails to run shows why, with a retry', (
      tester,
    ) async {
      await _pump(
        tester,
        http(
          run: (_) => const FakeStatus(403, {
            'error': 'forbidden',
            'message': 'missing permission quotations.read',
          }),
        ),
        const SavedReportScreen(id: 'r1'),
      );
      expect(find.text('missing permission quotations.read'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('result view', () {
    Future<void> show(WidgetTester tester, ReportRunResult r) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: ReportResultView(result: r)),
          ),
        ),
      );
    }

    testWidgets('a pie chart shows each share of the whole', (tester) async {
      await show(tester, ReportRunResult.fromJson(_result(chart: 'pie')));
      expect(find.textContaining('75,0 %'), findsOneWidget);
      expect(find.textContaining('25,0 %'), findsOneWidget);
    });

    testWidgets('a truncated pie says its shares are of the groups shown', (
      tester,
    ) async {
      final rows = [
        for (var i = 0; i < 35; i++) ['g$i', 10.0],
      ];
      await show(
        tester,
        ReportRunResult.fromJson(_result(chart: 'pie', rows: rows, total: 35)),
      );
      expect(find.text('Shares are of the 30 groups shown.'), findsOneWidget);
    });

    testWidgets('without a load-more button the shown row count is stated', (
      tester,
    ) async {
      await show(
        tester,
        ReportRunResult.fromJson(
          _result(
            rows: [
              ['a', 1.0],
            ],
            total: 5,
          ),
        ),
      );
      expect(find.text('1 of 5 rows shown'), findsOneWidget);
    });

    testWidgets('a line chart draws without errors', (tester) async {
      await show(tester, ReportRunResult.fromJson(_result(chart: 'line')));
      expect(find.byType(CustomPaint), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cells are formatted by type', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(reportCell(ctx, ReportFieldType.number, 1234.5), '1.234,5');
      expect(reportCell(ctx, ReportFieldType.number, 500.0), '500');
      expect(reportCell(ctx, ReportFieldType.date, '2027-01-31'), '31/01/2027');
      expect(reportCell(ctx, ReportFieldType.valueBool, true), 'Yes');
      expect(reportCell(ctx, ReportFieldType.valueBool, false), 'No');
      expect(reportCell(ctx, ReportFieldType.text, null), '');
      expect(reportCell(ctx, ReportFieldType.text, 'x'), 'x');
    });
  });

  group('builder', () {
    FakeHttp http({Map<String, Object? Function(Object?)> extra = const {}}) =>
        FakeHttp({
          'GET /api/v1/me': (_) => meJson(_writer),
          'GET /api/v1/custom-reports/catalog': (_) => _catalog(),
          'GET /api/v1/custom-reports/r1': (_) => _report(),
          'POST /api/v1/custom-reports/run': (_) => _result(),
          ...extra,
        });

    testWidgets('edits a stored report: previews it and saves the change', (
      tester,
    ) async {
      final h = http(
        extra: {
          'PUT /api/v1/custom-reports/r1': (_) => _report(name: 'Renamed'),
        },
      );
      await _pump(tester, h, const ReportBuilderPage(id: 'r1'));
      expect(find.text('Total by status'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      final run = h.bodies['POST /api/v1/custom-reports/run'] as Map;
      expect(run['limit'], 50);
      final def = run['definition'] as Map;
      expect(def['object'], 'quotation');
      expect(def['columns'], [
        {'field': 'quotation.total', 'summary': 'sum'},
      ]);
      expect(def['group_by'], [
        {'field': 'quotation.status'},
      ]);
      expect(find.text('accepted'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('report-name')),
        'Renamed',
      );
      await tester.tap(find.byKey(const ValueKey('report-shared')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('save-report')));
      await tester.tap(find.byKey(const ValueKey('save-report')));
      await tester.pumpAndSettle();
      final put = h.bodies['PUT /api/v1/custom-reports/r1'] as Map;
      expect(put['name'], 'Renamed');
      expect(put['shared'], true);
      expect((put['definition'] as Map)['chart'], {
        'kind': 'bar',
        'x': 'quotation.status',
        'y': 'quotation.total:sum',
      });
      expect(find.text('VIEW PAGE'), findsOneWidget);
    });

    testWidgets('adding columns twice picks distinct output keys', (
      tester,
    ) async {
      final h = http();
      await _pump(tester, h, const ReportBuilderPage());
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.byKey(const ValueKey('add-column')));
        await tester.tap(find.byKey(const ValueKey('add-column')));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      final def =
          (h.bodies['POST /api/v1/custom-reports/run'] as Map)['definition']
              as Map;
      final cols = (def['columns'] as List).map(
        (c) => '${c['field']}:${c['summary']}',
      );
      expect(cols.toSet().length, 2);
    });

    testWidgets('a new report needs a name and a column', (tester) async {
      final h = http();
      await _pump(tester, h, const ReportBuilderPage());
      await tester.ensureVisible(find.byKey(const ValueKey('save-report')));
      await tester.tap(find.byKey(const ValueKey('save-report')));
      await tester.pump();
      expect(find.text('Give the report a name.'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('report-name')), 'Mine');
      await tester.tap(find.byKey(const ValueKey('save-report')));
      await tester.pump();
      expect(find.text('Add at least one column.'), findsOneWidget);
      expect(h.requests, isNot(contains('POST /api/v1/custom-reports')));

      // Running without a column explains it as well.
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      expect(find.text('Add at least one column.'), findsWidgets);
      expect(h.requests, isNot(contains('POST /api/v1/custom-reports/run')));
    });

    testWidgets('builds a new report from scratch and saves it', (
      tester,
    ) async {
      final h = http(
        extra: {'POST /api/v1/custom-reports': (_) => _report(id: 'r9')},
      );
      await _pump(tester, h, const ReportBuilderPage());
      await tester.enterText(
        find.byKey(const ValueKey('report-name')),
        'My report',
      );

      await tester.ensureVisible(find.byKey(const ValueKey('add-column')));
      await tester.tap(find.byKey(const ValueKey('add-column')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('add-filter')));
      await tester.tap(find.byKey(const ValueKey('add-filter')));
      await tester.pump();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('filter-0')),
          matching: find.byType(TextFormField),
        ),
        'C00',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('add-group')));
      await tester.tap(find.byKey(const ValueKey('add-group')));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      final def =
          (h.bodies['POST /api/v1/custom-reports/run'] as Map)['definition']
              as Map;
      expect(def['object'], 'customer');
      // Grouping the report made the column a summary: a count of records.
      expect(def['columns'], [
        {'field': 'customer.records', 'summary': 'count'},
      ]);
      expect(def['group_by'], [
        {'field': 'customer.code'},
      ]);
      expect(def['filters'], [
        {'field': 'customer.code', 'op': 'eq', 'value': 'C00'},
      ]);

      await tester.ensureVisible(find.byKey(const ValueKey('save-report')));
      await tester.tap(find.byKey(const ValueKey('save-report')));
      await tester.pumpAndSettle();
      final post = h.bodies['POST /api/v1/custom-reports'] as Map;
      expect(post['name'], 'My report');
      expect(post['shared'], false);
      expect(find.text('VIEW PAGE'), findsOneWidget);
    });

    Map<String, Object?> relativeDef(Object? value) => {
      ..._definition(),
      'filters': [
        {'field': 'quotation.quote_date', 'op': 'gte', 'value': value},
      ],
    };

    testWidgets('a saved relative filter shows and runs unchanged', (
      tester,
    ) async {
      final value = {'relative': 'last_n_days', 'n': 30};
      final h = http(
        extra: {
          'GET /api/v1/custom-reports/r1': (_) =>
              _report(definition: relativeDef(value)),
        },
      );
      await _pump(tester, h, const ReportBuilderPage(id: 'r1'));
      expect(find.text('Relative to today'), findsOneWidget);
      expect(find.text('Last N days'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '30'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      final def =
          (h.bodies['POST /api/v1/custom-reports/run'] as Map)['definition']
              as Map;
      expect(def['filters'], [
        {'field': 'quotation.quote_date', 'op': 'gte', 'value': value},
      ]);
    });

    testWidgets('an invalid number of days blocks running', (tester) async {
      final h = http(
        extra: {
          'GET /api/v1/custom-reports/r1': (_) => _report(
            definition: relativeDef({'relative': 'next_n_days', 'n': 7}),
          ),
        },
      );
      await _pump(tester, h, const ReportBuilderPage(id: 'r1'));
      await tester.enterText(find.widgetWithText(TextFormField, '7'), '5000');
      await tester.pump();
      expect(
        find.text('Enter a whole number of days from 1 to 3660.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      expect(h.requests, isNot(contains('POST /api/v1/custom-reports/run')));
      expect(
        find.text('Enter a whole number of days from 1 to 3660.'),
        findsWidgets,
      );
    });

    testWidgets('a fixed date filter can be switched to relative', (
      tester,
    ) async {
      final h = http(
        extra: {
          'GET /api/v1/custom-reports/r1': (_) =>
              _report(definition: relativeDef('2027-01-31')),
        },
      );
      await _pump(tester, h, const ReportBuilderPage(id: 'r1'));
      await tester.tap(find.text('Fixed date'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relative to today').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Last month').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      final def =
          (h.bodies['POST /api/v1/custom-reports/run'] as Map)['definition']
              as Map;
      expect(def['filters'], [
        {
          'field': 'quotation.quote_date',
          'op': 'gte',
          'value': {'relative': 'last_month'},
        },
      ]);
    });

    testWidgets('related data can be added to the report', (tester) async {
      final h = http();
      await _pump(tester, h, const ReportBuilderPage());
      await tester.ensureVisible(find.byKey(const ValueKey('join-quotation')));
      await tester.tap(find.byKey(const ValueKey('join-quotation')));
      await tester.pump();
      // Fields of the joined object are offered, named with their object.
      await tester.ensureVisible(find.byKey(const ValueKey('add-column')));
      await tester.tap(find.byKey(const ValueKey('add-column')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      final def =
          (h.bodies['POST /api/v1/custom-reports/run'] as Map)['definition']
              as Map;
      expect(def['joins'], ['quotation']);
    });

    testWidgets('a refused preview shows the server message', (tester) async {
      await _pump(
        tester,
        http(
          extra: {
            'POST /api/v1/custom-reports/run': (_) => const FakeStatus(422, {
              'error': 'validation',
              'message': 'cannot group by \'quotation.total\'',
            }),
          },
        ),
        const ReportBuilderPage(id: 'r1'),
      );
      await tester.ensureVisible(find.byKey(const ValueKey('run-report')));
      await tester.tap(find.byKey(const ValueKey('run-report')));
      await tester.pumpAndSettle();
      expect(find.text('cannot group by \'quotation.total\''), findsOneWidget);
    });
  });
}
