import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/framework/form/one2many_line_editor.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('renders header, rows, add and remove actions on wide screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final rows = ['Line A', 'Line B'];
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _app(
          One2ManyLineEditor<String>(
            rows: rows,
            addButtonKey: const ValueKey('add'),
            addLabel: 'Add line',
            removeKeyBuilder: (i, _) => ValueKey('remove-$i'),
            onAdd: () => setState(() => rows.add('Line C')),
            onRemove: (i, _) => setState(() => rows.removeAt(i)),
            columns: [
              One2ManyColumn<String>(
                label: 'Description',
                cell: (_, _, r) => Text(r),
              ),
              One2ManyColumn<String>(
                label: 'Amount',
                width: 100,
                numeric: true,
                cell: (_, i, _) => Text('${(i + 1) * 10}'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Line A'), findsOneWidget);
    expect(find.text('Line B'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add')));
    await tester.pumpAndSettle();
    expect(find.text('Line C'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('remove-0')));
    await tester.pumpAndSettle();
    expect(find.text('Line A'), findsNothing);
    expect(find.text('Line B'), findsOneWidget);
  });

  testWidgets('hides add and remove controls when readOnly and shows emptyText', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        One2ManyLineEditor<String>(
          rows: const [],
          readOnly: true,
          emptyText: 'No lines yet',
          onAdd: () {},
          onRemove: (_, _) {},
          columns: [
            One2ManyColumn<String>(
              label: 'Description',
              cell: (_, _, r) => Text(r),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No lines yet'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);
  });

  testWidgets('wraps cleanly below narrowBreakpoint without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _app(
        One2ManyLineEditor<String>(
          rows: const ['Row 1'],
          onRemove: (_, _) {},
          columns: [
            One2ManyColumn<String>(
              label: 'Description',
              cell: (_, _, r) => SizedBox(width: 240, child: Text(r)),
            ),
            One2ManyColumn<String>(
              label: 'Qty',
              width: 100,
              numeric: true,
              cell: (_, _, _) => const Text('5'),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Description'), findsNothing);
    expect(find.text('Row 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
