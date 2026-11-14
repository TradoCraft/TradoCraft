import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/shared/search_picker.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

void main() {
  testWidgets('clearOnSelect allows picking several items in a row', (
    tester,
  ) async {
    final picked = <String>[];
    const items = ['UNIT-100', 'HOSE-25', 'PUMP-05'];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Column(
              children: [
                Text('picked: ${picked.join(',')}'),
                SearchPicker<String>(
                  label: 'Add product',
                  clearOnSelect: true,
                  display: (s) => s,
                  search: (q) async => items
                      .where((s) => s.toLowerCase().contains(q.toLowerCase()))
                      .toList(),
                  onSelected: (s) => setState(() => picked.add(s)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    for (final query in ['unit', 'hose']) {
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text(items.firstWhere((s) => s.toLowerCase().contains(query)))
            .last,
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
    }
    expect(picked, ['UNIT-100', 'HOSE-25']);
  });
}
