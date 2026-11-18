import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_harness.dart';

// Goldens are generated on Linux CI (default test font); regenerate there, not on other systems.
Widget _sampler() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          FilledButton(onPressed: () {}, child: const Text('Save')),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
          const SizedBox(width: 8),
          TextButton(onPressed: () {}, child: const Text('More')),
        ],
      ),
      const SizedBox(height: 12),
      const TextField(decoration: InputDecoration(labelText: 'Name')),
      const SizedBox(height: 12),
      const Card(
        child: Padding(padding: EdgeInsets.all(12), child: Text('A card')),
      ),
      const Divider(),
      DataTable(
        columns: const [
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Qty'), numeric: true),
        ],
        rows: const [
          DataRow(cells: [DataCell(Text('Widget')), DataCell(Text('3'))]),
        ],
      ),
    ],
  ),
);

void main() {
  for (final b in [Brightness.light, Brightness.dark]) {
    testWidgets('theme sampler ${b.name}', (tester) async {
      await pumpThemed(tester, _sampler(), brightness: b);
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('goldens/theme_sampler_${b.name}.png'),
      );
    });
  }
}
