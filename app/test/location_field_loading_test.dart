import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/features/inventory/inventory_common.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

Warehouse _main() => Warehouse.fromJson({
  'id': 'w1',
  'company_id': 'co',
  'code': 'MAIN',
  'name': 'Main warehouse',
  'kind': 'warehouse',
  'active': true,
  'locations': [
    {
      'id': 'l1',
      'company_id': 'co',
      'warehouse_id': 'w1',
      'code': 'MAIN',
      'name': 'Main warehouse',
      'active': true,
    },
  ],
});

Widget _host(Completer<List<Warehouse>> load, void Function(String?) pick) =>
    ProviderScope(
      overrides: [warehousesProvider.overrideWith((ref) => load.future)],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: LocationField(label: 'Put into', value: null, onChanged: pick),
        ),
      ),
    );

void main() {
  testWidgets(
    'a location field opened before the warehouses arrive offers them once they have',
    (tester) async {
      final load = Completer<List<Warehouse>>();
      String? picked;
      await tester.pumpWidget(_host(load, (v) => picked = v));
      await tester.pump();

      // Loading: the field has no items, so a tap opens no menu.
      final field = find.byType(DropdownButtonFormField<String>);
      await tester.tap(field, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('MAIN/MAIN'), findsNothing);

      // The answer arrives: the same field now offers the location, no reopening needed.
      load.complete([_main()]);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('MAIN/MAIN').last);
      await tester.pumpAndSettle();
      expect(picked, 'l1');
    },
  );
}
