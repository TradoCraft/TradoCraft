import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/shared/module_icon.dart';

void main() {
  testWidgets('ModuleIcon shows the SVG of the named icon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ModuleIcon('quotations'))),
    );
    await tester.pump();
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  test('every icon named by the navigation exists in assets/icons', () {
    final shell = File('lib/app/shell.dart').readAsStringSync();
    final names = RegExp(r"'/[a-z/]+': '([a-z_]+)'")
        .allMatches(shell)
        .map((m) => m.group(1)!)
        .toSet();
    expect(names.length, greaterThan(10));
    for (final n in names) {
      expect(File('assets/icons/$n.svg').existsSync(), true, reason: n);
    }
  });

  test('the app icon and its variants exist', () {
    for (final f in ['app_icon', 'app_icon_maskable', 'app_mark']) {
      expect(File('assets/branding/$f.svg').existsSync(), true, reason: f);
    }
  });
}
