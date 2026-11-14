import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradocraft_app/app/zoom.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';

void main() {
  testWidgets('Ctrl plus, minus and 0 zoom the app and the zoom is stored', (
    tester,
  ) async {
    final store = MemoryKvStore();
    final container = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ZoomShell(child: Scaffold(body: Text('hello'))),
        ),
      ),
    );
    expect(container.read(zoomProvider), 1.0);

    Future<void> ctrl(LogicalKeyboardKey k) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(k);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    await ctrl(LogicalKeyboardKey.equal);
    await ctrl(LogicalKeyboardKey.equal);
    expect(container.read(zoomProvider), 1.2);
    expect(store.data[ZoomNotifier.key], '1.2');
    await ctrl(LogicalKeyboardKey.minus);
    expect(container.read(zoomProvider), 1.1);
    await ctrl(LogicalKeyboardKey.digit0);
    expect(container.read(zoomProvider), 1.0);
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('the stored zoom is loaded, a bad value is ignored', (
    tester,
  ) async {
    final store = MemoryKvStore()..data[ZoomNotifier.key] = '1.5';
    final container = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);
    container.read(zoomProvider);
    await tester.pump();
    expect(container.read(zoomProvider), 1.5);

    store.data[ZoomNotifier.key] = '9';
    final other = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(store)],
    );
    addTearDown(other.dispose);
    other.read(zoomProvider);
    await tester.pump();
    expect(other.read(zoomProvider), 1.0);
  });

  testWidgets('Ctrl with the mouse wheel zooms, the wheel alone does not', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [kvStoreProvider.overrideWithValue(MemoryKvStore())],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ZoomShell(child: Scaffold(body: Text('hello'))),
        ),
      ),
    );
    final centre = tester.getCenter(find.text('hello'));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(centre));

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
    expect(container.read(zoomProvider), 1.0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -20)));
    expect(container.read(zoomProvider), 1.1);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 20)));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(container.read(zoomProvider), 0.9);
  });
}
