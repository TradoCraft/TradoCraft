import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import 'platform.dart';

/// A key and whether Shift is part of the chord.
class ShortcutChord {
  /// Creates a chord. [physical] also matches the key by position (used for the digit row, whose
  /// logical key changes with Shift and with the keyboard layout).
  const ShortcutChord(this.key, {this.physical, this.shift = false});

  /// The logical key (layout aware: the letter the user sees on the key).
  final LogicalKeyboardKey key;

  /// An alternative match by key position.
  final PhysicalKeyboardKey? physical;

  /// Whether Shift must be held (and nothing else may differ).
  final bool shift;
}

// The digit chords of the menu entries; the web ones add Shift.
const _d1 = ShortcutChord(
  LogicalKeyboardKey.digit1,
  physical: PhysicalKeyboardKey.digit1,
);
const _d2 = ShortcutChord(
  LogicalKeyboardKey.digit2,
  physical: PhysicalKeyboardKey.digit2,
);
const _d3 = ShortcutChord(
  LogicalKeyboardKey.digit3,
  physical: PhysicalKeyboardKey.digit3,
);
const _d4 = ShortcutChord(
  LogicalKeyboardKey.digit4,
  physical: PhysicalKeyboardKey.digit4,
);
const _d5 = ShortcutChord(
  LogicalKeyboardKey.digit5,
  physical: PhysicalKeyboardKey.digit5,
);
const _d6 = ShortcutChord(
  LogicalKeyboardKey.digit6,
  physical: PhysicalKeyboardKey.digit6,
);
const _d7 = ShortcutChord(
  LogicalKeyboardKey.digit7,
  physical: PhysicalKeyboardKey.digit7,
);
const _d8 = ShortcutChord(
  LogicalKeyboardKey.digit8,
  physical: PhysicalKeyboardKey.digit8,
);
const _d9 = ShortcutChord(
  LogicalKeyboardKey.digit9,
  physical: PhysicalKeyboardKey.digit9,
);

/// Everything a keyboard shortcut can do, in the style of common business-app shortcuts so users
/// can move between products. See ADR 0060.
///
/// Most chords use the primary modifier ([primaryModifierLabel]: Alt, Ctrl on macOS); [palette]
/// and [help] always use Ctrl or Cmd.
enum ShortcutAction {
  /// Back: pops the active tab's route.
  back(ShortcutChord(LogicalKeyboardKey.keyB)),

  /// Create a record in the current scope.
  create(ShortcutChord(LogicalKeyboardKey.keyC)),

  /// Home: the first permitted menu entry.
  home(ShortcutChord(LogicalKeyboardKey.keyH)),

  /// Discard the edits (reset the form or close the tab).
  discard(ShortcutChord(LogicalKeyboardKey.keyJ)),

  /// Save.
  save(ShortcutChord(LogicalKeyboardKey.keyS)),

  /// Load more on a list. (The previous-page key P is not implemented: no list pages yet.)
  nextPage(ShortcutChord(LogicalKeyboardKey.keyN)),

  /// Focus the search field of the scope.
  search(ShortcutChord(LogicalKeyboardKey.keyQ)),

  /// Menu entry 1. Menu entries 1 to 9 select the entry of the permission-filtered navigation.
  /// On the web the browser keeps Alt+digit (tab switching in Firefox), so there it is
  /// Alt+Shift+digit.
  menu1(_d1, webOverride: _wd1),

  /// Menu entry 2.
  menu2(_d2, webOverride: _wd2),

  /// Menu entry 3.
  menu3(_d3, webOverride: _wd3),

  /// Menu entry 4.
  menu4(_d4, webOverride: _wd4),

  /// Menu entry 5.
  menu5(_d5, webOverride: _wd5),

  /// Menu entry 6.
  menu6(_d6, webOverride: _wd6),

  /// Menu entry 7.
  menu7(_d7, webOverride: _wd7),

  /// Menu entry 8.
  menu8(_d8, webOverride: _wd8),

  /// Menu entry 9.
  menu9(_d9, webOverride: _wd9),

  /// New to-do (Shift+T).
  newTodo(ShortcutChord(LogicalKeyboardKey.keyT, shift: true)),

  /// Search a knowledge-base article.
  kbSearch(ShortcutChord(LogicalKeyboardKey.keyF)),

  /// Share a knowledge-base article (Shift+S).
  kbShare(ShortcutChord(LogicalKeyboardKey.keyS, shift: true)),

  /// The command palette: Ctrl or Cmd with K.
  palette(ShortcutChord(LogicalKeyboardKey.keyK), usesPrimary: false),

  /// The shortcut help: Ctrl or Cmd with the slash.
  help(ShortcutChord(LogicalKeyboardKey.slash), usesPrimary: false);

  const ShortcutAction(this.chord, {this.usesPrimary = true, this.webOverride});

  /// The chord on desktop and mobile.
  final ShortcutChord chord;

  /// True for the primary modifier (Alt, Ctrl on macOS); false for Ctrl or Cmd.
  final bool usesPrimary;

  /// The chord on the web, when it differs.
  final ShortcutChord? webOverride;

  /// The menu entries, in order (index 0 is entry 1).
  static const menus = [
    menu1,
    menu2,
    menu3,
    menu4,
    menu5,
    menu6,
    menu7,
    menu8,
    menu9,
  ];

  /// The action for menu entry [n] (1 to 9), or null beyond that.
  static ShortcutAction? menu(int n) =>
      n >= 1 && n <= menus.length ? menus[n - 1] : null;

  /// The chord in effect: the web override on the web.
  ShortcutChord chordFor({bool web = kIsWeb}) =>
      web ? (webOverride ?? chord) : chord;

  static String _keyText(ShortcutChord c) =>
      c.key == LogicalKeyboardKey.slash ? '/' : c.key.keyLabel.toUpperCase();

  /// The text of the corner badge: the letter or digit, with an arrow for Shift chords.
  String get hintLabel => chord.shift ? '⇧${_keyText(chord)}' : _keyText(chord);

  /// The full chord for people, e.g. `Alt+Shift+2` or `Ctrl+K`.
  String describe({bool web = kIsWeb}) {
    final c = chordFor(web: web);
    return [
      if (usesPrimary) primaryModifierLabel else 'Ctrl',
      if (c.shift) 'Shift',
      _keyText(c),
    ].join('+');
  }

  /// The name of the action, in the language of the user.
  String label(AppLocalizations l) => switch (this) {
    back => l.shortcutBack,
    create => l.shortcutCreate,
    home => l.shortcutHome,
    discard => l.shortcutDiscard,
    save => l.shortcutSave,
    nextPage => l.shortcutNextPage,
    search => l.shortcutSearch,
    newTodo => l.shortcutNewTodo,
    kbSearch => l.shortcutKbSearch,
    kbShare => l.shortcutKbShare,
    palette => l.shortcutPalette,
    help => l.shortcutHelp,
    _ => l.shortcutMenuItem(menus.indexOf(this) + 1),
  };

  /// Letters bound to editing in macOS text fields (emacs style, with Ctrl). Our Ctrl chords on
  /// these letters must leave a focused text field alone.
  static final _macTextKeys = {
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyB,
    LogicalKeyboardKey.keyD,
    LogicalKeyboardKey.keyE,
    LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyH,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.keyN,
    LogicalKeyboardKey.keyO,
    LogicalKeyboardKey.keyP,
    LogicalKeyboardKey.keyT,
  };

  /// The action [event] triggers with the modifiers now held, or null. [editing] says a text field
  /// has the focus (see [_macTextKeys]).
  static ShortcutAction? fromEvent(
    KeyEvent event, {
    bool web = kIsWeb,
    bool editing = false,
  }) {
    final kb = HardwareKeyboard.instance;
    final ctrl = kb.isControlPressed,
        alt = kb.isAltPressed,
        meta = kb.isMetaPressed,
        shift = kb.isShiftPressed;
    for (final a in values) {
      final c = a.chordFor(web: web);
      if (shift != c.shift) continue;
      final keyOk =
          event.logicalKey == c.key ||
          (c.physical != null && event.physicalKey == c.physical);
      if (!keyOk) continue;
      if (a.usesPrimary) {
        final ok = isMac ? (ctrl && !alt && !meta) : (alt && !ctrl && !meta);
        if (!ok) continue;
        if (isMac && editing && _macTextKeys.contains(c.key)) continue;
      } else {
        if (!((ctrl != meta) && !alt)) continue;
        if (isMac && editing && ctrl && _macTextKeys.contains(c.key)) continue;
      }
      return a;
    }
    return null;
  }
}

const _wd1 = ShortcutChord(
  LogicalKeyboardKey.digit1,
  physical: PhysicalKeyboardKey.digit1,
  shift: true,
);
const _wd2 = ShortcutChord(
  LogicalKeyboardKey.digit2,
  physical: PhysicalKeyboardKey.digit2,
  shift: true,
);
const _wd3 = ShortcutChord(
  LogicalKeyboardKey.digit3,
  physical: PhysicalKeyboardKey.digit3,
  shift: true,
);
const _wd4 = ShortcutChord(
  LogicalKeyboardKey.digit4,
  physical: PhysicalKeyboardKey.digit4,
  shift: true,
);
const _wd5 = ShortcutChord(
  LogicalKeyboardKey.digit5,
  physical: PhysicalKeyboardKey.digit5,
  shift: true,
);
const _wd6 = ShortcutChord(
  LogicalKeyboardKey.digit6,
  physical: PhysicalKeyboardKey.digit6,
  shift: true,
);
const _wd7 = ShortcutChord(
  LogicalKeyboardKey.digit7,
  physical: PhysicalKeyboardKey.digit7,
  shift: true,
);
const _wd8 = ShortcutChord(
  LogicalKeyboardKey.digit8,
  physical: PhysicalKeyboardKey.digit8,
  shift: true,
);
const _wd9 = ShortcutChord(
  LogicalKeyboardKey.digit9,
  physical: PhysicalKeyboardKey.digit9,
  shift: true,
);
