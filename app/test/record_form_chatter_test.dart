import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/framework/form/record_form_controller.dart';
import 'package:tradocraft_app/framework/form/record_form_view.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

Future<void> _pump(
  WidgetTester t, {
  required double width,
  bool beside = true,
  Widget? chatter,
}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final controller = RecordFormController<String>(
    initial: 'x',
    versionOf: (_) => 1,
  );
  addTearDown(controller.dispose);
  await t.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RecordFormView<String>(
            controller: controller,
            title: 'Record',
            reportDirty: false,
            chatterBeside: beside,
            chatter: chatter,
            body: const SizedBox(key: ValueKey('body'), height: 100),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

const _chatter = SizedBox(key: ValueKey('chatter'), height: 50);

void main() {
  final body = find.byKey(const ValueKey('body'));
  final chatter = find.byKey(const ValueKey('chatter'));

  testWidgets('no chatter, no extra space', (t) async {
    await _pump(t, width: 1400);
    expect(chatter, findsNothing);
  });

  testWidgets('beside the sheet when the page is wide', (t) async {
    await _pump(t, width: 1400, chatter: _chatter);
    expect(t.getTopLeft(chatter).dx, greaterThan(t.getTopRight(body).dx));
    expect(t.getSize(chatter).width, 380);
  });

  testWidgets('below the sheet when the page is narrow', (t) async {
    await _pump(t, width: 900, chatter: _chatter);
    expect(t.getTopLeft(chatter).dy, greaterThan(t.getBottomLeft(body).dy));
  });

  testWidgets('below the sheet when the form asks for the full width', (
    t,
  ) async {
    await _pump(t, width: 1400, beside: false, chatter: _chatter);
    expect(t.getTopLeft(chatter).dy, greaterThan(t.getBottomLeft(body).dy));
  });

  test('a chatter tick notifies its listeners', () {
    final tick = ChatterTick();
    var n = 0;
    tick.addListener(() => n++);
    tick.fire();
    tick.fire();
    expect(n, 2);
    tick.dispose();
  });
}
