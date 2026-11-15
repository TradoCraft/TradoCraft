import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/app/shortcuts/actions.dart';
import 'package:tradocraft_app/app/shortcuts/button_scan.dart';
import 'package:tradocraft_app/app/shortcuts/host.dart';
import 'package:tradocraft_app/app/shortcuts/registry.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';

const _altBadge = ValueKey('auto-key-badge');
const _stdBadge = ValueKey('std-key-badge');

void main() {
  late ProviderContainer container;

  /// Mounts [home] in an app with the shortcut host and the modal observer.
  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorObservers: [
            ModalShortcutObserver(container.read(shortcutRegistryProvider)),
          ],
          builder: (context, child) => ShortcutsHost(child: child!),
          home: Scaffold(body: home),
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
    bool meta = false,
  }) async {
    if (alt) await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handled = await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    if (alt) await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    return handled;
  }

  Set<String> badges(WidgetTester t, Key key) => {
    for (final w in t.widgetList<DecoratedBox>(find.byKey(key)))
      ((w.child! as Padding).child! as Text).data!,
  };

  group('letters', () {
    test('first letter of the first free word, then any letter of the label', () {
      expect(
        assignLetters(['Save', 'Save draft', 'Send', 'Delete']),
        ['s', 'd', 'e', 'l'],
      );
    });

    test('accents are normalised, only a-z is used', () {
      expect(assignLetters(['Éditer', 'Über', '12 3']), ['e', 'u', null]);
    });

    test('reserved letters are skipped, and a free one is found', () {
      expect(assignLetters(['Back', 'Home'], reserved: {'b', 'h'}), [
        'a',
        'o',
      ]);
    });

    test('a priority label keeps its natural letter', () {
      expect(
        assignLetters(['Close', 'Cancel'], priority: {1}),
        ['l', 'c'],
      );
    });

    test('the same input gives the same output', () {
      final labels = ['One', 'Only', 'Open', 'Ox'];
      expect(assignLetters(labels), assignLetters(labels));
      expect(assignLetters(labels).toSet().length, 4);
    });

    test('labels are classified by the localized words', () async {
      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(classifyLabel('Save', l), ButtonRole.save);
      expect(classifyLabel('save draft', l), ButtonRole.save);
      expect(classifyLabel('Cancel', l), ButtonRole.cancel);
      expect(classifyLabel('Close', l), ButtonRole.cancel);
      expect(classifyLabel('Delete', l), ButtonRole.confirm);
      expect(classifyLabel('New customer', l), ButtonRole.create);
      expect(classifyLabel('Whatever', l), ButtonRole.none);
      final nl = await AppLocalizations.delegate.load(const Locale('nl'));
      expect(classifyLabel('Opslaan', nl), ButtonRole.save);
      expect(classifyLabel('Annuleren', nl), ButtonRole.cancel);
    });
  });

  group('standard chords', () {
    testWidgets('Ctrl+S activates Save on a page', (t) async {
      var saved = 0;
      await pump(
        t,
        Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('Other')),
            TextButton(onPressed: () => saved++, child: const Text('Save')),
          ],
        ),
      );
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isTrue);
      expect(saved, 1);
    });

    testWidgets('Ctrl+S with no Save button is left to the platform', (t) async {
      await pump(
        t,
        TextButton(onPressed: () {}, child: const Text('Other')),
      );
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isFalse);
    });

    testWidgets('Ctrl+S in a dialog presses its Save, not the page one', (
      t,
    ) async {
      var pageSaved = 0, dialogSaved = 0;
      await pump(
        t,
        Builder(
          builder: (c) => Column(
            children: [
              TextButton(
                onPressed: () => pageSaved++,
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => AlertDialog(
                    content: const Text('dlg'),
                    actions: [
                      TextButton(
                        onPressed: () {},
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => dialogSaved++,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isTrue);
      expect(dialogSaved, 1);
      expect(pageSaved, 0);
    });

    testWidgets('a dialog without Save does not reach the page Save', (t) async {
      var pageSaved = 0;
      await pump(
        t,
        Builder(
          builder: (c) => Column(
            children: [
              TextButton(
                onPressed: () => pageSaved++,
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => const AlertDialog(content: Text('dlg')),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isFalse);
      expect(pageSaved, 0);
    });

    testWidgets('a registered handler wins over the button', (t) async {
      var button = 0, handler = 0;
      await pump(
        t,
        ShortcutScope(
          actions: {ShortcutAction.save: () => handler++},
          child: TextButton(
            onPressed: () => button++,
            child: const Text('Save'),
          ),
        ),
      );
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isTrue);
      expect((handler, button), (1, 0));
    });

    testWidgets('Ctrl+Enter confirms the dialog with its primary action', (
      t,
    ) async {
      bool? result;
      await pump(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: c,
                builder: (d) => AlertDialog(
                  content: const Text('Really?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('No thanks'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Proceed'),
                    ),
                  ],
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.enter, ctrl: true), isTrue);
      expect(result, isTrue);
      expect(find.text('Really?'), findsNothing);
    });

    testWidgets('Ctrl+Enter on a page presses the Save button only', (t) async {
      var saved = 0, filled = 0;
      await pump(
        t,
        Column(
          children: [
            FilledButton(onPressed: () => filled++, child: const Text('Go')),
            TextButton(onPressed: () => saved++, child: const Text('Save')),
          ],
        ),
      );
      expect(await chord(t, LogicalKeyboardKey.enter, ctrl: true), isTrue);
      expect((saved, filled), (1, 0));
    });

    testWidgets('Esc closes a dialog through its Cancel button', (t) async {
      var cancelled = 0;
      await pump(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showDialog<void>(
              context: c,
              barrierDismissible: false,
              builder: (d) => AlertDialog(
                content: const Text('dlg'),
                actions: [
                  TextButton(
                    onPressed: () {
                      cancelled++;
                      Navigator.pop(d);
                    },
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(await chord(t, LogicalKeyboardKey.escape), isTrue);
      expect(cancelled, 1);
      expect(find.text('dlg'), findsNothing);
    });

    testWidgets('Esc on a page without a handler or Cancel does nothing', (
      t,
    ) async {
      await pump(t, TextButton(onPressed: () {}, child: const Text('Other')));
      expect(await chord(t, LogicalKeyboardKey.escape), isFalse);
    });

    testWidgets('Esc on a page presses a Cancel button', (t) async {
      var n = 0;
      await pump(
        t,
        TextButton(onPressed: () => n++, child: const Text('Cancel')),
      );
      expect(await chord(t, LogicalKeyboardKey.escape), isTrue);
      expect(n, 1);
    });

    testWidgets('Esc leaves an open popup menu to the framework', (t) async {
      await pump(
        t,
        PopupMenuButton<int>(
          itemBuilder: (_) => [const PopupMenuItem(value: 1, child: Text('i'))],
        ),
      );
      await t.tap(find.byType(PopupMenuButton<int>));
      await t.pumpAndSettle();
      expect(find.text('i'), findsOneWidget);
      await chord(t, LogicalKeyboardKey.escape);
      expect(find.text('i'), findsNothing);
    });

    testWidgets('Ctrl+N presses the New button, Ctrl+F focuses the search', (
      t,
    ) async {
      var created = 0;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await pump(
        t,
        Column(
          children: [
            FilledButton(
              onPressed: () => created++,
              child: const Text('New customer'),
            ),
            TextField(
              focusNode: focus,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search',
              ),
            ),
          ],
        ),
      );
      expect(await chord(t, LogicalKeyboardKey.keyN, ctrl: true), isTrue);
      expect(created, 1);
      expect(await chord(t, LogicalKeyboardKey.keyF, ctrl: true), isTrue);
      expect(focus.hasFocus, isTrue);
    });

    testWidgets('macOS: Cmd+S saves, Ctrl+S is an automatic key', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        var saved = 0;
        await pump(
          t,
          TextButton(onPressed: () => saved++, child: const Text('Save')),
        );
        expect(await chord(t, LogicalKeyboardKey.keyS, meta: true), isTrue);
        expect(saved, 1);
        // Ctrl is the primary modifier there: Ctrl+S presses the button holding S, same result.
        expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isTrue);
        expect(saved, 2);
        // Alt does nothing on macOS.
        expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isFalse);
        expect(saved, 2);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('automatic Alt keys', () {
    Widget page(List<String> log) => Builder(
      builder: (c) => Column(
        children: [
          TextButton(onPressed: () => log.add('save'), child: const Text('Save')),
          TextButton(onPressed: () => log.add('cancel'), child: const Text('Cancel')),
          const TextButton(onPressed: null, child: Text('Delete')),
          TextButton(onPressed: () => log.add('edit'), child: const Text('Éditer')),
          TextButton(onPressed: () => log.add('home'), child: const Text('Home')),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => log.add('refresh'),
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: c,
              builder: (d) => AlertDialog(
                content: const Text('dlg'),
                actions: [
                  TextButton(
                    onPressed: () {
                      log.add('dlg-save');
                    },
                    child: const Text('Save as'),
                  ),
                  TextButton(
                    onPressed: () {
                      log.add('dlg-close');
                      Navigator.pop(d);
                    },
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Open'),
          ),
        ],
      ),
    );

    testWidgets('Alt shows a unique letter on every enabled button', (t) async {
      await pump(t, page([]));
      expect(find.byKey(_altBadge), findsNothing);
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      // Delete is disabled. Save S, Cancel C, Éditer E, Home (h is Home) O, Refresh R, Open P.
      expect(find.byKey(_altBadge), findsNWidgets(6));
      expect(badges(t, _altBadge), {'S', 'C', 'E', 'O', 'R', 'P'});
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.byKey(_altBadge), findsNothing);
    });

    testWidgets('the letter presses the button, accents included', (t) async {
      final log = <String>[];
      await pump(t, page(log));
      expect(await chord(t, LogicalKeyboardKey.keyE, alt: true), isTrue);
      expect(await chord(t, LogicalKeyboardKey.keyR, alt: true), isTrue);
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isTrue);
      expect(log, ['edit', 'refresh', 'save']);
      // Disabled Delete (d) and unused letters do nothing.
      expect(await chord(t, LogicalKeyboardKey.keyD, alt: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.keyZ, alt: true), isFalse);
      // Reserved: Alt+H is the Home chord, not the Home button.
      await chord(t, LogicalKeyboardKey.keyH, alt: true);
      expect(log, isNot(contains('home')));
    });

    testWidgets('only the topmost dialog gets letters', (t) async {
      final log = <String>[];
      await pump(t, page(log));
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(find.byKey(_altBadge), findsNWidgets(2));
      expect(badges(t, _altBadge), {'S', 'C'});
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isTrue);
      expect(log, ['dlg-save']);
      expect(await chord(t, LogicalKeyboardKey.keyC, alt: true), isTrue);
      expect(log, ['dlg-save', 'dlg-close']);
      // Back on the page the letters are the page ones again.
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isTrue);
      expect(log.last, 'save');
    });

    testWidgets('reserved letters of the fixed chords are never assigned', (
      t,
    ) async {
      await pump(
        t,
        Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('Back')),
            TextButton(onPressed: () {}, child: const Text('Join')),
            TextButton(onPressed: () {}, child: const Text('Quit')),
            TextButton(onPressed: () {}, child: const Text('Next')),
          ],
        ),
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      final letters = badges(t, _altBadge);
      expect(letters.length, 4);
      expect(letters.intersection({'B', 'J', 'Q', 'N', 'H', 'F', 'L'}), isEmpty);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });

    testWidgets('badges never change the layout and take no pointer', (t) async {
      await pump(t, page([]));
      final before = t.getRect(find.text('Save'));
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      expect(t.getRect(find.text('Save')), before);
      expect(
        find.ancestor(of: find.byKey(_altBadge).first, matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });

    testWidgets('no key fires after the window lost the focus', (t) async {
      final log = <String>[];
      await pump(t, page(log));
      await t.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await t.pump();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.byKey(_altBadge), findsNothing);
      // The Alt key-up went to another window; a later letter must not count as Alt+letter.
      await t.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      expect(log, isEmpty);
      await t.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    });

    testWidgets('an input method composing text keeps its keys', (t) async {
      final log = <String>[];
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pump(
        t,
        Column(
          children: [
            TextField(controller: controller),
            TextButton(onPressed: () => log.add('save'), child: const Text('Save')),
          ],
        ),
      );
      await t.tap(find.byType(TextField));
      await t.pump();
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.keyS, alt: true), isFalse);
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isFalse);
      expect(log, isEmpty);
      controller.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
      );
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true), isTrue);
      expect(log, ['save']);
    });
  });

  group('standard chord badges', () {
    testWidgets('Ctrl shows S, Esc and Enter on the matching buttons', (t) async {
      await pump(
        t,
        Column(
          children: [
            TextButton(onPressed: () {}, child: const Text('Save')),
            TextButton(onPressed: () {}, child: const Text('Cancel')),
            TextButton(onPressed: () {}, child: const Text('Other')),
            const TextButton(onPressed: null, child: Text('Close')),
          ],
        ),
      );
      expect(find.byKey(_stdBadge), findsNothing);
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(badges(t, _stdBadge), {'S', 'Esc'});
      expect(find.byKey(_altBadge), findsNothing);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(find.byKey(_stdBadge), findsNothing);
    });

    testWidgets('a dialog shows Enter on its primary action', (t) async {
      await pump(
        t,
        Builder(
          builder: (c) => Column(
            children: [
              TextButton(onPressed: () {}, child: const Text('Save')),
              TextButton(
                onPressed: () => showDialog<void>(
                  context: c,
                  builder: (_) => AlertDialog(
                    content: const Text('dlg'),
                    actions: [
                      TextButton(onPressed: () {}, child: const Text('Back off')),
                      FilledButton(onPressed: () {}, child: const Text('Proceed')),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(badges(t, _stdBadge), {'Enter'});
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('macOS shows the standard badges on Cmd, the letters on Ctrl', (
      t,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pump(
          t,
          TextButton(onPressed: () {}, child: const Text('Save')),
        );
        await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await t.pump();
        expect(badges(t, _stdBadge), {'S'});
        expect(find.byKey(_altBadge), findsNothing);
        await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.pump();
        expect(find.byKey(_stdBadge), findsNothing);
        expect(badges(t, _altBadge), {'S'});
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('data entry', () {
    testWidgets('Enter moves to the next field, Shift+Enter back', (t) async {
      final f = List.generate(4, (_) => FocusNode());
      addTearDown(() {
        for (final n in f) {
          n.dispose();
        }
      });
      var submitted = 0;
      await pump(
        t,
        Column(
          children: [
            TextField(focusNode: f[0]),
            TextField(focusNode: f[1], onSubmitted: (_) => submitted++),
            TextField(focusNode: f[2], maxLines: 3),
            TextField(focusNode: f[3]),
          ],
        ),
      );
      f[0].requestFocus();
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.enter), isTrue);
      expect(f[1].hasFocus, isTrue);
      // A field that submits keeps submitting: the key is not ours.
      expect(await chord(t, LogicalKeyboardKey.enter), isFalse);
      expect(f[1].hasFocus, isTrue);
      await t.testTextInput.receiveAction(TextInputAction.done);
      expect(submitted, 1);
      // A multi-line field keeps its new line.
      f[2].requestFocus();
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.enter), isFalse);
      expect(f[2].hasFocus, isTrue);
      f[3].requestFocus();
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.enter, shift: true), isTrue);
      expect(f[2].hasFocus, isTrue);
    });

    testWidgets('Enter does not move while an input method composes', (t) async {
      final c = TextEditingController();
      final a = FocusNode(), b = FocusNode();
      addTearDown(() {
        c.dispose();
        a.dispose();
        b.dispose();
      });
      await pump(
        t,
        Column(
          children: [
            TextField(controller: c, focusNode: a),
            TextField(focusNode: b),
          ],
        ),
      );
      a.requestFocus();
      await t.pump();
      c.value = const TextEditingValue(
        text: 'ab',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      );
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.enter), isFalse);
      expect(a.hasFocus, isTrue);
    });

    testWidgets('a dialog opens with the cursor in its first field', (t) async {
      final first = FocusNode(), second = FocusNode();
      addTearDown(() {
        first.dispose();
        second.dispose();
      });
      await pump(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showDialog<void>(
              context: c,
              builder: (_) => AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(focusNode: first),
                    TextField(focusNode: second),
                  ],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(first.hasFocus, isTrue);
    });

    testWidgets('a field that asks for the focus itself keeps it', (t) async {
      final first = FocusNode(), second = FocusNode();
      addTearDown(() {
        first.dispose();
        second.dispose();
      });
      await pump(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showDialog<void>(
              context: c,
              builder: (_) => AlertDialog(
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(focusNode: first),
                    TextField(focusNode: second, autofocus: true),
                  ],
                ),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(second.hasFocus, isTrue);
    });

    testWidgets('a number field selects all when reached by keyboard', (t) async {
      final text = TextEditingController(text: 'abc');
      final amount = TextEditingController(text: '1250.50');
      addTearDown(() {
        text.dispose();
        amount.dispose();
      });
      final a = FocusNode(), n = FocusNode();
      addTearDown(() {
        a.dispose();
        n.dispose();
      });
      await pump(
        t,
        Column(
          children: [
            TextField(controller: text, focusNode: a),
            TextField(
              controller: amount,
              focusNode: n,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
      );
      a.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(n.hasFocus, isTrue);
      expect(amount.selection, const TextSelection(baseOffset: 0, extentOffset: 7));
      // Typing replaces it.
      t.testTextInput.enterText('9');
      await t.pump();
      expect(amount.text, '9');
    });

    testWidgets('clicking into a number field puts the caret where clicked', (
      t,
    ) async {
      final amount = TextEditingController(text: '1250.50');
      addTearDown(amount.dispose);
      await pump(
        t,
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      );
      await t.tap(find.byType(TextField));
      await t.pumpAndSettle();
      expect(amount.selection.isCollapsed, isTrue);
    });

    testWidgets('a mouse click on a number field keeps the caret where it landed', (
      t,
    ) async {
      final amount = TextEditingController(text: '1234.50');
      addTearDown(amount.dispose);
      await pump(
        t,
        TextField(
          controller: amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      );
      // A real mouse puts the focus highlight in "traditional" mode, like the keyboard does.
      final g = await t.startGesture(
        t.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.mouse,
      );
      await g.up();
      await t.pumpAndSettle();
      expect(amount.selection.isCollapsed, isTrue);
    });
  });

  group('review fixes', () {
    testWidgets('Ctrl+/ opens help with and without Shift (the slash needs Shift on some layouts)', (
      t,
    ) async {
      var help = 0, saved = 0;
      await pump(
        t,
        ShortcutScope(
          actions: {ShortcutAction.help: () => help++},
          child: TextButton(onPressed: () => saved++, child: const Text('Save')),
        ),
      );
      expect(await chord(t, LogicalKeyboardKey.slash, ctrl: true), isTrue);
      expect(await chord(t, LogicalKeyboardKey.slash, ctrl: true, shift: true), isTrue);
      expect(help, 2);
      // The exact Shift check stays for everything else: Ctrl+Shift+S is not Save.
      expect(await chord(t, LogicalKeyboardKey.keyS, ctrl: true, shift: true), isFalse);
      expect(saved, 0);
    });

    testWidgets('a dialog with only a search field keeps it for Ctrl+F, the page behind loses it', (
      t,
    ) async {
      late BuildContext ctx;
      await pump(
        t,
        Builder(
          builder: (c) {
            ctx = c;
            return const Column(
              children: [TextField(decoration: InputDecoration(hintText: 'Search'))],
            );
          },
        ),
      );
      showDialog<void>(
        context: ctx,
        builder: (_) => const AlertDialog(
          content: TextField(decoration: InputDecoration(hintText: 'Search')),
        ),
      );
      await t.pumpAndSettle();
      // Focus is on the dialog's field by autofocus; move it away first.
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump();
      expect(await chord(t, LogicalKeyboardKey.keyF, ctrl: true), isTrue);
      final dialogField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(EditableText),
      );
      expect(t.widget<EditableText>(dialogField).focusNode.hasFocus, isTrue);
    });

    test('Save draft counts as Save in every language, also where it does not start with Save', () async {
      for (final code in ['en', 'nl', 'de', 'fr', 'es']) {
        final l = await AppLocalizations.delegate.load(Locale(code));
        expect(classifyLabel(l.saveDraft, l), ButtonRole.save, reason: code);
        expect(classifyLabel(l.save, l), ButtonRole.save, reason: code);
      }
    });

    testWidgets('Ctrl+S reaches Save again when it is enabled while Ctrl is still held', (
      t,
    ) async {
      var saved = 0;
      final busy = ValueNotifier(true);
      addTearDown(busy.dispose);
      await pump(
        t,
        ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (_, b, _) => TextButton(
            onPressed: b ? null : () => saved++,
            child: const Text('Save'),
          ),
        ),
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      busy.value = false; // the save that was running has finished
      await t.pump();
      final handled = await t.sendKeyDownEvent(LogicalKeyboardKey.keyS);
      await t.sendKeyUpEvent(LogicalKeyboardKey.keyS);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(handled, isTrue);
      expect(saved, 1);
    });

    testWidgets('Enter still lands on the next field when the platform also sends "done" for the old one', (
      t,
    ) async {
      // On the web and on the desktop the text input reports an Enter as the action "done", which
      // unfocuses the field it is delivered to. If the focus had already moved, "done" would land on
      // the new field and leave nothing focused.
      final a = FocusNode(), b = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await pump(t, Column(children: [TextField(focusNode: a), TextField(focusNode: b)]));
      a.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      await t.pump();
      expect(b.hasFocus, isTrue);
    });

    testWidgets('Enter and Shift+Enter skip the action buttons between fields', (t) async {
      final a = FocusNode(), b = FocusNode();
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await pump(
        t,
        Column(
          children: [
            TextField(focusNode: a),
            IconButton(onPressed: () {}, tooltip: 'Remove', icon: const Icon(Icons.close)),
            TextButton(onPressed: () {}, child: const Text('Other')),
            TextField(focusNode: b),
          ],
        ),
      );
      a.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(b.hasFocus, isTrue, reason: 'the buttons between the fields are skipped');
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(a.hasFocus, isTrue);
    });
  });
}
