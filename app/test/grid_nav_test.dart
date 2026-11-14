import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tradocraft_app/l10n/app_localizations.dart';
import 'package:tradocraft_app/shared/entity_list.dart';
import 'package:tradocraft_app/shared/grid_key_nav.dart';

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

Future<void> _key(
  WidgetTester t,
  LogicalKeyboardKey key, {
  bool ctrl = false,
}) async {
  if (ctrl) await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await t.sendKeyEvent(key);
  if (ctrl) await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await t.pump();
}

void main() {
  group('GridKeyNav on a table of fields', () {
    late List<List<FocusNode>> nodes;

    Future<void> pumpGrid(WidgetTester t) async {
      nodes = List.generate(4, (_) => List.generate(3, (_) => FocusNode()));
      addTearDown(() {
        for (final r in nodes) {
          for (final n in r) {
            n.dispose();
          }
        }
      });
      await t.pumpWidget(
        _app(
          GridKeyNav(
            child: Column(
              children: [
                for (final r in nodes)
                  Row(
                    children: [
                      for (final n in r)
                        Expanded(child: TextField(focusNode: n)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('Up and Down keep the column', (t) async {
      await pumpGrid(t);
      nodes[1][1].requestFocus();
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(nodes[2][1].hasFocus, isTrue);
      await _key(t, LogicalKeyboardKey.arrowUp);
      await _key(t, LogicalKeyboardKey.arrowUp);
      expect(nodes[0][1].hasFocus, isTrue);
      // At the top there is nothing further: the key is left alone.
      await _key(t, LogicalKeyboardKey.arrowUp);
      expect(nodes[0][1].hasFocus, isTrue);
    });

    testWidgets('Ctrl+Left and Ctrl+Right go to the ends of the row', (t) async {
      await pumpGrid(t);
      nodes[2][1].requestFocus();
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowRight, ctrl: true);
      expect(nodes[2][2].hasFocus, isTrue);
      await _key(t, LogicalKeyboardKey.arrowLeft, ctrl: true);
      expect(nodes[2][0].hasFocus, isTrue);
    });

    testWidgets('Ctrl+Up and Ctrl+Down go to the first and last row', (t) async {
      await pumpGrid(t);
      nodes[1][2].requestFocus();
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowDown, ctrl: true);
      expect(nodes[3][2].hasFocus, isTrue);
      await _key(t, LogicalKeyboardKey.arrowUp, ctrl: true);
      expect(nodes[0][2].hasFocus, isTrue);
    });

    testWidgets('Home and End in a field stay caret keys', (t) async {
      await pumpGrid(t);
      nodes[1][1].requestFocus();
      await t.pump();
      await _key(t, LogicalKeyboardKey.home);
      await _key(t, LogicalKeyboardKey.end);
      expect(nodes[1][1].hasFocus, isTrue);
    });
  });

  group('EntityList keyboard', () {
    Future<List<String>> pumpList(WidgetTester t, {int count = 60}) async {
      t.view.physicalSize = const Size(1200, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final opened = <String>[];
      final all = List.generate(
        count,
        (i) => 'Item ${i.toString().padLeft(2, '0')}',
      );
      await t.pumpWidget(
        _app(
          EntityList<String>(
            title: 'Things',
            load: (q, offset, limit) async =>
                (all.skip(offset).take(limit).toList(), all.length),
            columns: [EntityColumn('Name', (s) => s)],
            onOpen: (s) async {
              opened.add(s);
              return false;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      return opened;
    }

    bool rowFocused(WidgetTester t, String text) {
      final row = find.ancestor(
        of: find.text(text),
        matching: find.byType(InkWell),
      );
      return Focus.of(t.element(row.first)).hasFocus;
    }

    testWidgets('Down from the search field enters the rows, arrows move', (
      t,
    ) async {
      await pumpList(t);
      await t.tap(find.byType(TextField));
      await t.pump();
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(rowFocused(t, 'Item 00'), isTrue);
      await _key(t, LogicalKeyboardKey.arrowDown);
      expect(rowFocused(t, 'Item 01'), isTrue);
      await _key(t, LogicalKeyboardKey.arrowUp);
      expect(rowFocused(t, 'Item 00'), isTrue);
    });

    testWidgets('End and Home jump to the last and first row', (t) async {
      await pumpList(t);
      await t.tap(find.byType(TextField));
      await _key(t, LogicalKeyboardKey.arrowDown);
      await _key(t, LogicalKeyboardKey.end);
      await t.pumpAndSettle();
      expect(rowFocused(t, 'Item 49'), isTrue);
      await _key(t, LogicalKeyboardKey.home);
      await t.pumpAndSettle();
      expect(rowFocused(t, 'Item 00'), isTrue);
      await _key(t, LogicalKeyboardKey.arrowDown, ctrl: true);
      await t.pumpAndSettle();
      expect(rowFocused(t, 'Item 49'), isTrue);
      await _key(t, LogicalKeyboardKey.arrowUp, ctrl: true);
      await t.pumpAndSettle();
      expect(rowFocused(t, 'Item 00'), isTrue);
    });

    testWidgets('Down past the built rows scrolls on', (t) async {
      await pumpList(t);
      await t.tap(find.byType(TextField));
      await _key(t, LogicalKeyboardKey.arrowDown);
      for (var i = 0; i < 30; i++) {
        await _key(t, LogicalKeyboardKey.arrowDown);
        await t.pumpAndSettle();
      }
      expect(rowFocused(t, 'Item 30'), isTrue);
    });

    testWidgets('Enter opens the focused row', (t) async {
      final opened = await pumpList(t);
      await t.tap(find.byType(TextField));
      await _key(t, LogicalKeyboardKey.arrowDown);
      await _key(t, LogicalKeyboardKey.arrowDown);
      await _key(t, LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(opened, ['Item 01']);
    });
  });
}
