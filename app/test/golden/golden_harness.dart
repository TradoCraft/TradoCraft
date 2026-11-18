import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/core/theme/app_theme.dart';

/// Pumps [child] under the app theme at a fixed size, for golden tests.
///
/// Goldens are generated on Linux CI with the default test font, so the images do not depend on
/// the fonts of a developer machine. Regenerate with `flutter test --update-goldens <file>`.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
  Size size = const Size(480, 360),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: Scaffold(body: RepaintBoundary(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}
