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

  test(
    'a completed operation shows the chatter at once, a failed one does not',
    () async {
      final controller = RecordFormController<String>(
        initial: 'x',
        versionOf: (_) => 1,
      );
      addTearDown(controller.dispose);
      var ticks = 0;
      controller.chatterTick.addListener(() => ticks++);
      expect(await controller.run(() async => 'saved'), isTrue);
      expect(ticks, 1);
      expect(await controller.run(() async => throw 'refused'), isFalse);
      expect(ticks, 1, reason: 'nothing was written');
    },
  );

  testWidgets('the chatter keeps its state when the page changes width', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(1400, 1200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final controller = RecordFormController<String>(
      initial: 'x',
      versionOf: (_) => 1,
    );
    addTearDown(controller.dispose);
    Widget app() => ProviderScope(
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
            chatter: const _Draft(),
            body: const SizedBox(key: ValueKey('body'), height: 100),
          ),
        ),
      ),
    );
    await t.pumpWidget(app());
    await t.enterText(find.byType(TextField), 'half written note');
    final beside = t.getTopLeft(find.byType(_Draft)).dx;
    // narrower: the panel moves below the sheet
    await t.binding.setSurfaceSize(const Size(900, 1200));
    await t.pumpWidget(app());
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byType(_Draft)).dx, lessThan(beside));
    expect(find.text('half written note'), findsOneWidget);
  });
}

/// A stand-in chatter with a draft, to see that its state survives a re-layout.
class _Draft extends StatefulWidget {
  const _Draft();

  @override
  State<_Draft> createState() => _DraftState();
}

class _DraftState extends State<_Draft> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(controller: _text);
}
