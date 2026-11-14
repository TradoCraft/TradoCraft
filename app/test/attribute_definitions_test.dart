import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/admin/admin_page.dart';
import 'package:tradocraft_app/features/admin/attribute_definitions_page.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

Map<String, Object?> _def(
  String key,
  String kind, {
  bool active = true,
  List<Map<String, String>> options = const [],
}) => {
  'id': 'id-$key',
  'key': key,
  'label': 'Label $key',
  'kind': kind,
  'unit': null,
  'options': options,
  'scope': 'product',
  'sort_order': 0,
  'active': active,
};

Future<void> _pump(
  WidgetTester tester,
  FakeHttp http, [
  Widget page = const AttributeDefinitionsPage(),
]) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [dioProvider.overrideWithValue(fakeDio(http))],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              ref.watch(meProvider);
              return page;
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists definitions, marking inactive ones', (tester) async {
    await _pump(
      tester,
      FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.write']),
        'GET /api/v1/attribute-definitions': (_) => [
          _def('dial', 'range'),
          _def('old', 'text', active: false),
        ],
      }),
    );
    expect(find.text('Label dial'), findsOneWidget);
    expect(find.byKey(const ValueKey('attrdef-old')), findsOneWidget);
    expect(find.textContaining('inactive'), findsOneWidget);
  });

  testWidgets('shows an empty state', (tester) async {
    await _pump(
      tester,
      FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.write']),
        'GET /api/v1/attribute-definitions': (_) => [],
      }),
    );
    expect(find.byKey(const ValueKey('attrdef-empty')), findsOneWidget);
  });

  testWidgets('creates a select definition with options', (tester) async {
    final h = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/attribute-definitions': (_) => [],
      'POST /api/v1/attribute-definitions': (b) => _def('motion', 'select'),
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('attrdef-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('attrdef-key')), 'motion');
    await tester.enterText(
      find.byKey(const ValueKey('attrdef-label')),
      'Motion',
    );
    await tester.tap(find.byKey(const ValueKey('attrdef-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select').last);
    await tester.pumpAndSettle();
    // A select needs options.
    await tester.tap(find.byKey(const ValueKey('attrdef-save')));
    await tester.pumpAndSettle();
    expect(find.text('A select needs at least one option.'), findsOneWidget);
    expect(h.requests, isNot(contains('POST /api/v1/attribute-definitions')));

    await tester.tap(find.byKey(const ValueKey('attrdef-option-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attrdef-option-value-0')),
      'flying',
    );
    await tester.enterText(
      find.byKey(const ValueKey('attrdef-option-label-0')),
      'Flying',
    );
    await tester.tap(find.byKey(const ValueKey('attrdef-save')));
    await tester.pumpAndSettle();
    expect(h.bodies['POST /api/v1/attribute-definitions'], {
      'key': 'motion',
      'label': 'Motion',
      'kind': 'select',
      'options': [
        {'label': 'Flying', 'value': 'flying'},
      ],
      'scope': 'product',
      'sort_order': 0,
      'active': true,
    });
  });

  testWidgets('refuses an invalid key and duplicate option values', (
    tester,
  ) async {
    final h = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/attribute-definitions': (_) => [],
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('attrdef-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attrdef-key')),
      'Bad Key',
    );
    await tester.enterText(find.byKey(const ValueKey('attrdef-label')), 'X');
    await tester.tap(find.byKey(const ValueKey('attrdef-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('lowercase'), findsOneWidget);
    expect(h.requests, isNot(contains('POST /api/v1/attribute-definitions')));
  });

  testWidgets('edits a definition and deactivates it', (tester) async {
    final h = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/attribute-definitions': (_) => [_def('dial', 'range')],
      'PUT /api/v1/attribute-definitions/id-dial': (b) => _def('dial', 'range'),
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('attrdef-edit-dial')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('attrdef-label')),
      'Dial size',
    );
    await tester.tap(find.byKey(const ValueKey('attrdef-active')));
    await tester.tap(find.byKey(const ValueKey('attrdef-save')));
    await tester.pumpAndSettle();
    final body = h.bodies['PUT /api/v1/attribute-definitions/id-dial'] as Map;
    expect(body['label'], 'Dial size');
    expect(body['active'], false);
    expect(body['kind'], 'range');
  });

  testWidgets('delete asks for confirmation and surfaces the 409 message', (
    tester,
  ) async {
    const msg =
        'attribute dial is in use on 3 products and cannot be deleted; deactivate it instead';
    final h = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/attribute-definitions': (_) => [_def('dial', 'range')],
      'DELETE /api/v1/attribute-definitions/id-dial': (_) =>
          const FakeStatus(409, {'error': 'conflict', 'message': msg}),
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('attrdef-del-dial')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attrdef-delete-confirm')));
    await tester.pumpAndSettle();
    expect(
      h.requests,
      contains('DELETE /api/v1/attribute-definitions/id-dial'),
    );
    expect(find.text(msg), findsOneWidget);
    expect(find.text('Label dial'), findsOneWidget);
  });

  testWidgets('without products.write there are no edit controls', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.read']),
        'GET /api/v1/attribute-definitions': (_) => [_def('dial', 'range')],
      }),
    );
    expect(find.byKey(const ValueKey('attrdef-new')), findsNothing);
    expect(find.byKey(const ValueKey('attrdef-edit-dial')), findsNothing);
  });

  testWidgets('the scope is chosen from product and the baseline types', (
    tester,
  ) async {
    final h = FakeHttp({
      'GET /api/v1/me': (_) => meJson(['products.write']),
      'GET /api/v1/attribute-definitions': (_) => [],
      'GET /api/v1/baseline-item-types': (_) => [
        {
          'id': 't1',
          'code': 'bell',
          'name': 'Bell',
          'allowed_parent_codes': <String>[],
          'allow_top_level': true,
          'sort_order': 0,
          'active': true,
        },
      ],
      'POST /api/v1/attribute-definitions': (b) => _def('weight', 'number'),
    });
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('attrdef-new')));
    await tester.pumpAndSettle();
    expect(
      find
          .byType(TextField)
          .evaluate()
          .where(
            (e) =>
                (e.widget as TextField).key == const ValueKey('attrdef-scope'),
          ),
      isEmpty,
      reason: 'no longer free text',
    );
    await tester.enterText(find.byKey(const ValueKey('attrdef-key')), 'weight');
    await tester.enterText(
      find.byKey(const ValueKey('attrdef-label')),
      'Weight',
    );
    await tester.tap(find.byKey(const ValueKey('attrdef-scope')));
    await tester.pumpAndSettle();
    expect(find.text('Product'), findsWidgets);
    await tester.tap(find.text('Bell (bell)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('attrdef-save')));
    await tester.pumpAndSettle();
    expect(
      (h.bodies['POST /api/v1/attribute-definitions'] as Map)['scope'],
      'bell',
    );
  });

  testWidgets('key, type and scope are locked when editing', (tester) async {
    await _pump(
      tester,
      FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.write']),
        'GET /api/v1/attribute-definitions': (_) => [_def('dial', 'range')],
      }),
    );
    await tester.tap(find.byKey(const ValueKey('attrdef-edit-dial')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('attrdef-scope')),
          )
          .onChanged,
      isNull,
    );
  });

  testWidgets('the admin page offers the attributes to product writers', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeHttp({
        'GET /api/v1/me': (_) => meJson(['products.write']),
        'GET /api/v1/attribute-definitions': (_) => [_def('dial', 'range')],
      }),
      const AdminPage(),
    );
    expect(find.text('Label dial'), findsOneWidget);
    expect(find.byKey(const ValueKey('attrdef-new')), findsOneWidget);
  });
}
