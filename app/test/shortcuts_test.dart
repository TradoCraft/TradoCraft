import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tradocraft_app/app/api.dart';
import 'package:tradocraft_app/app/detail_routes.dart';
import 'package:tradocraft_app/app/shell.dart';
import 'package:tradocraft_app/app/shortcuts/actions.dart';
import 'package:tradocraft_app/app/shortcuts/host.dart';
import 'package:tradocraft_app/app/shortcuts/registry.dart';
import 'package:tradocraft_app/app/workspace.dart';
import 'package:tradocraft_app/features/field/offline/kv_store.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

import 'fake_http.dart';

/// Counts what each stand-in detail screen's shortcuts did, by screen name.
final _saved = <String>[];

/// A detail screen with a text field, a Save shortcut and a button that pushes another screen
/// (so Back has something to pop).
class _Probe extends StatelessWidget {
  const _Probe(this.name);
  final String name;

  @override
  Widget build(BuildContext context) {
    return ShortcutScope(
      actions: {ShortcutAction.save: () => _saved.add(name)},
      child: Scaffold(
        body: Column(
          children: [
            Text('screen $name'),
            TextField(key: ValueKey('field-$name')),
            TextButton(
              onPressed: () => context.push('/orders/$name-in'),
              child: Text('push-$name'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget? _probes(Uri uri) =>
    isDetailLocation(uri.toString()) ? _Probe(uri.pathSegments.last) : null;

const _ids = ['orders.read', 'helpdesk.read', 'quotations.read'];

void main() {
  late GoRouter router;
  late ProviderContainer container;

  setUp(_saved.clear);

  Future<void> pump(
    WidgetTester tester, {
    double width = 1400,
    List<String> perms = _ids,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final http = FakeHttp({'GET /api/v1/me': (_) => meJson(perms)});
    container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(fakeDio(http)),
        kvStoreProvider.overrideWithValue(MemoryKvStore()),
        detailScreenProvider.overrideWithValue(_probes),
      ],
    );
    addTearDown(container.dispose);
    router = GoRouter(
      observers: [
        ModalShortcutObserver(container.read(shortcutRegistryProvider)),
      ],
      initialLocation: '/orders',
      routes: [
        ShellRoute(
          builder: (c, s, child) =>
              AppShell(location: s.matchedLocation, child: child),
          routes: [
            GoRoute(
              path: '/quotations',
              builder: (_, _) => const Text('QUOTATIONS LIST'),
            ),
            GoRoute(
              path: '/orders',
              builder: (_, _) => const Text('ORDERS LIST'),
            ),
            GoRoute(
              path: '/orders/:id',
              builder: (_, s) => DetailPortal(location: s.uri.toString()),
            ),
            GoRoute(
              path: '/helpdesk',
              builder: (_, _) => const Text('HELPDESK LIST'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('en'),
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ShortcutsHost(child: child!),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Presses [key] with the modifiers; returns whether the app took it.
  Future<bool> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool alt = false,
    bool ctrl = false,
    bool shift = false,
  }) async {
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handled = await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    return handled;
  }

  WorkspaceNotifier ws() => container.read(workspaceProvider.notifier);

  group('menu digits', () {
    testWidgets('Alt+n selects the n-th permitted destination', (t) async {
      await pump(t);
      // quotations, orders, helpdesk: the destinations of these permissions, in menu order.
      expect(await chord(t, LogicalKeyboardKey.digit3, alt: true), isTrue);
      expect(find.text('HELPDESK LIST'), findsOneWidget);
      expect(await chord(t, LogicalKeyboardKey.digit1, alt: true), isTrue);
      expect(find.text('QUOTATIONS LIST'), findsOneWidget);
      expect(await chord(t, LogicalKeyboardKey.digit2, alt: true), isTrue);
      expect(find.text('ORDERS LIST'), findsOneWidget);
    });

    testWidgets('a user with fewer permissions has a shorter list', (t) async {
      await pump(t, perms: ['orders.read', 'helpdesk.read']);
      // orders, helpdesk: Alt+2 is helpdesk here (it was orders above), Alt+3 does nothing.
      expect(await chord(t, LogicalKeyboardKey.digit3, alt: true), isFalse);
      expect(find.text('ORDERS LIST'), findsOneWidget);
      expect(await chord(t, LogicalKeyboardKey.digit2, alt: true), isTrue);
      expect(find.text('HELPDESK LIST'), findsOneWidget);
    });

    testWidgets('on the web the digits need Shift too', (t) async {
      await pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final e = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit2,
        logicalKey: LogicalKeyboardKey.at,
        timeStamp: Duration.zero,
      );
      expect(ShortcutAction.fromEvent(e, web: true), ShortcutAction.menu2);
      expect(ShortcutAction.fromEvent(e, web: false), isNull);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final plain = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.digit2,
        logicalKey: LogicalKeyboardKey.digit2,
        timeStamp: Duration.zero,
      );
      expect(ShortcutAction.fromEvent(plain, web: true), isNull);
      expect(ShortcutAction.fromEvent(plain, web: false), ShortcutAction.menu2);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(ShortcutAction.menu2.describe(web: true), 'Alt+Shift+2');
    });

    testWidgets('on macOS Ctrl is the modifier, not Alt', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(t);
        expect(await chord(t, LogicalKeyboardKey.digit3, alt: true), isFalse);
        expect(find.text('ORDERS LIST'), findsOneWidget);
        expect(await chord(t, LogicalKeyboardKey.digit3, ctrl: true), isTrue);
        expect(find.text('HELPDESK LIST'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('unhandled combinations pass through', (t) async {
      await pump(t);
      expect(await chord(t, LogicalKeyboardKey.keyZ, alt: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.digit2), isFalse);
      expect(await chord(t, LogicalKeyboardKey.digit2, ctrl: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.digit2, alt: true, ctrl: true),
          isFalse);
      // Home needs no handler outside the shell; Create has no scope yet (phase B).
      expect(await chord(t, LogicalKeyboardKey.keyC, alt: true), isFalse);
    });

    testWidgets('H shows the first permitted section and the main area', (
      t,
    ) async {
      await pump(t);
      ws().open('/orders/a');
      await t.pumpAndSettle();
      expect(container.read(workspaceProvider).active, isNotNull);
      expect(await chord(t, LogicalKeyboardKey.keyH, alt: true), isTrue);
      expect(container.read(workspaceProvider).active, isNull);
      expect(find.text('QUOTATIONS LIST'), findsOneWidget);
    });
  });

  group('hint badges', () {
    testWidgets('show while the modifier is held and hide on release', (
      t,
    ) async {
      await pump(t);
      expect(find.byKey(const ValueKey('key-hint-badge')), findsNothing);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.byKey(const ValueKey('key-hint-badge')), findsNWidgets(3));
      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.byKey(const ValueKey('key-hint-badge')), findsNothing);
    });

    testWidgets('the narrow bar has them too and layout does not move', (
      t,
    ) async {
      await pump(t, width: 500);
      final before = t.getRect(find.text('Orders').first);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.byKey(const ValueKey('key-hint-badge')), findsNWidgets(3));
      expect(t.getRect(find.text('Orders').first), before);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
    });

    testWidgets('window blur and lifecycle changes clear them', (t) async {
      await pump(t);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.byKey(const ValueKey('key-hint-badge')), findsNWidgets(3));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.byKey(const ValueKey('key-hint-badge')), findsNothing);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });

    testWidgets('macOS shows them on Ctrl, not on Alt', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(t);
        await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await t.pump();
        expect(find.byKey(const ValueKey('key-hint-badge')), findsNothing);
        await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.pump();
        expect(find.byKey(const ValueKey('key-hint-badge')), findsNWidgets(3));
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pump();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('a badge needs a handler: Back is hidden at a tab root', (
      t,
    ) async {
      await pump(t);
      ws().open('/orders/a');
      await t.pumpAndSettle();
      final registry = container.read(shortcutRegistryProvider);
      expect(registry.isEnabled(ShortcutAction.back), isFalse);
      expect(await chord(t, LogicalKeyboardKey.keyB, alt: true), isFalse);
      await t.tap(find.text('push-a'));
      await t.pumpAndSettle();
      expect(registry.isEnabled(ShortcutAction.back), isTrue);
      expect(find.text('screen a-in'), findsOneWidget);
      expect(await chord(t, LogicalKeyboardKey.keyB, alt: true), isTrue);
      expect(find.text('screen a-in'), findsNothing);
      expect(find.text('screen a'), findsOneWidget);
      expect(registry.isEnabled(ShortcutAction.back), isFalse);
    });
  });

  group('scopes', () {
    testWidgets('only the active tab takes part', (t) async {
      await pump(t);
      ws().open('/orders/a');
      ws().open('/orders/b');
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isTrue);
      expect(_saved, ['b']);
      ws().focus(container.read(workspaceProvider).tabs.first.id);
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isTrue);
      expect(_saved, ['b', 'a']);
      ws().focusHome();
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isFalse);
      expect(_saved, ['b', 'a']);
    });

    testWidgets('a dialog on top blocks the shell and gets its own keys', (
      t,
    ) async {
      await pump(t);
      var dialogSaves = 0;
      showDialog<void>(
        context: t.element(find.byType(AppShell)),
        builder: (_) => ShortcutScope(
          layer: ShortcutLayer.dialog,
          actions: {ShortcutAction.save: () => dialogSaves++},
          child: const AlertDialog(content: Text('a dialog')),
        ),
      );
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.digit1, alt: true), isFalse);
      expect(find.text('ORDERS LIST'), findsOneWidget);
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isTrue);
      expect(dialogSaves, 1);
      Navigator.of(t.element(find.text('a dialog'))).pop();
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.digit1, alt: true), isTrue);
      expect(find.text('QUOTATIONS LIST'), findsOneWidget);
    });

    testWidgets('any dialog is modal without declaring a scope', (t) async {
      await pump(t);
      showDialog<void>(
        context: t.element(find.byType(AppShell)),
        builder: (_) => const AlertDialog(content: Text('plain dialog')),
      );
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.digit1, alt: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.keyH, alt: true), isFalse);
      expect(find.text('ORDERS LIST'), findsOneWidget);
      Navigator.of(t.element(find.text('plain dialog'))).pop();
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.digit1, alt: true), isTrue);
    });

    testWidgets('the unsaved-changes dialog of a tab blocks shell and Back', (
      t,
    ) async {
      await pump(t);
      final id = ws().open('/orders/a');
      await t.pumpAndSettle();
      await t.tap(find.text('push-a'));
      await t.pumpAndSettle();
      ws().dirtyOf(id).value = true;
      await t.tap(find.byTooltip('Close tab'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(await chord(t, LogicalKeyboardKey.digit1, alt: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.keyB, alt: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.keyH, alt: true), isFalse);
      expect(find.text('screen a-in'), findsOneWidget);
    });

    testWidgets('a dialog scope is active although the tab is not', (t) async {
      await pump(t);
      ws().open('/orders/a');
      await t.pumpAndSettle();
      var n = 0;
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ShortcutActivity(
              active: false,
              child: ShortcutScope(
                layer: ShortcutLayer.dialog,
                actions: {ShortcutAction.save: () => n++},
                child: const SizedBox(),
              ),
            ),
          ),
        ),
      );
      container.read(shortcutRegistryProvider).resolve(ShortcutAction.save)!();
      expect(n, 1);
    });

    testWidgets('a dialog above a tab shadows the tab handler', (t) async {
      await pump(t);
      ws().open('/orders/a');
      await t.pumpAndSettle();
      showDialog<void>(
        context: t.element(find.byType(AppShell)),
        builder: (_) => ShortcutScope(
          layer: ShortcutLayer.dialog,
          actions: const {},
          child: const AlertDialog(content: Text('a dialog')),
        ),
      );
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isFalse);
      expect(_saved, isEmpty);
    });
  });

  group('text fields', () {
    testWidgets('the modifier with a letter inserts nothing', (t) async {
      await pump(t);
      ws().open('/orders/a');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('field-a')));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      // No handler for Z: it passes through, and the key's character is not text for us.
      final handled = await t.sendKeyDownEvent(
        LogicalKeyboardKey.keyZ,
        character: 'z',
      );
      expect(handled, isFalse);
      // A handled one (Save) is consumed, not typed.
      final saved = await t.sendKeyDownEvent(
        LogicalKeyboardKey.keyS,
        character: 's',
      );
      expect(saved, isTrue);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(
        t
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('field-a')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(find.text('s'), findsNothing);
      expect(_saved, ['a']);
    });

    testWidgets('macOS: Ctrl+B in a text field stays text editing', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(t);
        ws().open('/orders/a');
        await t.pumpAndSettle();
        await t.tap(find.text('push-a'));
        await t.pumpAndSettle();
        // Back is available...
        expect(
          container
              .read(shortcutRegistryProvider)
              .isEnabled(ShortcutAction.back),
          isTrue,
        );
        // ...but not while a text field has the focus (Ctrl+B moves the cursor there).
        await t.tap(find.byKey(const ValueKey('field-a-in')));
        await t.pumpAndSettle();
        // (The text field's own shortcut takes the key, so the return value says nothing.)
        await chord(t, LogicalKeyboardKey.keyB, ctrl: true);
        expect(find.text('screen a-in'), findsOneWidget);
        // Digits and Save are no text keys: still ours.
        expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('display', () {
    test('the badge and the text follow the chord in effect', () {
      expect(ShortcutAction.menu2.hintLabelFor(web: false), '2');
      expect(ShortcutAction.menu2.hintLabelFor(web: true), '⇧2');
      expect(ShortcutAction.menu2.describe(web: false), 'Alt+2');
      expect(ShortcutAction.menu2.describe(web: true), 'Alt+Shift+2');
      expect(ShortcutAction.save.hintLabelFor(web: true), 'S');
      expect(ShortcutAction.kbShare.hintLabelFor(web: false), '⇧S');
    });
  });

  group('registry', () {
    test('topmost layer wins, newest within a layer, null is absent', () {
      final r = ShortcutStack();
      addTearDown(r.dispose);
      final calls = <String>[];
      final shell = r.register(ShortcutLayer.shell, {
        ShortcutAction.save: () => calls.add('shell'),
        ShortcutAction.back: () => calls.add('shell-back'),
      });
      r.register(ShortcutLayer.page, {
        ShortcutAction.save: () => calls.add('page1'),
      });
      final page2 = r.register(ShortcutLayer.page, {
        ShortcutAction.save: () => calls.add('page2'),
        ShortcutAction.back: null,
      });
      r.resolve(ShortcutAction.save)!();
      r.resolve(ShortcutAction.back)!();
      expect(calls, ['page2', 'shell-back']);
      r.unregister(page2);
      r.resolve(ShortcutAction.save)!();
      expect(calls.last, 'page1');
      r.update(shell, {});
      expect(r.resolve(ShortcutAction.back), isNull);
    });
  });
}
