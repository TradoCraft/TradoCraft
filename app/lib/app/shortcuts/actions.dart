import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import 'platform.dart';

/// Which modifier a chord needs.
enum ChordMod {
  /// Alt (Ctrl on macOS): the fixed chords and the automatic button keys.
  primary,

  /// Ctrl (Cmd on macOS): the standard chords (save, confirm, find, create, palette, help).
  standard,

  /// No modifier (Esc). Handled after the focused widget had its say, see `ShortcutsHost`.
  none,
}

/// A key and whether Shift is part of the chord.
class ShortcutChord {
  /// Creates a chord. [physical] also matches the key by position (used for the digit row, whose
  /// logical key changes with Shift and with the keyboard layout).
  const ShortcutChord(
    this.key, {
    this.physical,
    this.shift = false,
    this.mod = ChordMod.primary,
    this.anyShift = false,
  });

  /// Whether Shift may be held or not. For a character that some keyboard layouts only reach with
  /// Shift (the slash is Shift+7 on German, Dutch and many other layouts): the key event then
  /// carries the character, and Shift must not stop the chord.
  final bool anyShift;

  /// The modifier the chord needs.
  final ChordMod mod;

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
/// The fixed navigation chords use the primary modifier ([primaryModifierLabel]: Alt, Ctrl on
/// macOS). The standard chords ([save], [confirm], [find], [create], [palette], [help]) use
/// [standardModifierLabel] (Ctrl, Cmd on macOS); [cancel] is Esc alone.
enum ShortcutAction {
  /// Back: pops the active tab's route.
  back(ShortcutChord(LogicalKeyboardKey.keyB)),

  /// Create a record in the current scope. Ctrl+N; browsers keep Ctrl+N, so the web uses Alt+C.
  create(
    ShortcutChord(LogicalKeyboardKey.keyN, mod: ChordMod.standard),
    webOverride: ShortcutChord(LogicalKeyboardKey.keyC),
  ),

  /// Home: the home screen.
  home(ShortcutChord(LogicalKeyboardKey.home)),

  /// Discard the edits (reset the form or close the tab).
  discard(ShortcutChord(LogicalKeyboardKey.keyJ)),

  /// Save: Ctrl+S (Cmd+S).
  save(ShortcutChord(LogicalKeyboardKey.keyS, mod: ChordMod.standard)),

  /// Confirm the topmost dialog or submit the form: Ctrl+Enter.
  confirm(ShortcutChord(LogicalKeyboardKey.enter, mod: ChordMod.standard)),

  /// Cancel the topmost dialog or leave the form: Esc.
  cancel(ShortcutChord(LogicalKeyboardKey.escape, mod: ChordMod.none)),

  /// Focus the search field of the page: Ctrl+F.
  find(ShortcutChord(LogicalKeyboardKey.keyF, mod: ChordMod.standard)),

  /// Add a line to the document on screen (focus its "add product" picker).
  addLine(ShortcutChord(LogicalKeyboardKey.keyL)),

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

  ticketEscalate(ShortcutChord(LogicalKeyboardKey.keyE, shift: true)),
  ticketDelegate(ShortcutChord(LogicalKeyboardKey.keyD, shift: true)),
  ticketMerge(ShortcutChord(LogicalKeyboardKey.keyM, shift: true)),
  ticketSplit(ShortcutChord(LogicalKeyboardKey.keyX, shift: true)),

  /// The command palette: Ctrl or Cmd with K.
  palette(ShortcutChord(LogicalKeyboardKey.keyK, mod: ChordMod.standard)),

  /// Select all / Deselect all (e.g. in filter menus): Ctrl+Shift+A / Cmd+Shift+A.
  selectAll(
    ShortcutChord(LogicalKeyboardKey.keyA, mod: ChordMod.standard, shift: true),
  ),

  /// The shortcut help: Ctrl or Cmd with the slash (with Shift where the layout needs it).
  help(
    ShortcutChord(
      LogicalKeyboardKey.slash,
      mod: ChordMod.standard,
      anyShift: true,
    ),
  ),

  /// Tutorial: Do this step for me / Run this step / Start next chapter / Next.
  tutorialNext(ShortcutChord(LogicalKeyboardKey.arrowRight)),

  /// Tutorial: Back to the previous step.
  tutorialBack(ShortcutChord(LogicalKeyboardKey.arrowLeft)),

  /// Tutorial: Back to the chapter map.
  tutorialMap(ShortcutChord(LogicalKeyboardKey.arrowUp)),

  /// Tutorial: Take me there.
  tutorialTakeMe(ShortcutChord(LogicalKeyboardKey.arrowDown)),

  /// Tutorial: Pause or show control.
  tutorialPauseOrShowControl(ShortcutChord(LogicalKeyboardKey.escape));

  const ShortcutAction(this.chord, {this.webOverride});

  /// The chord on desktop and mobile.
  final ShortcutChord chord;

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

  /// The chord in effect: user override if any, else the web override on the web, else default.
  ShortcutChord chordFor({bool web = kIsWeb}) =>
      ShortcutBindings.overrideFor(this) ?? (web ? (webOverride ?? chord) : chord);

  /// The default chord for this platform (ignoring user overrides).
  ShortcutChord defaultChord({bool web = kIsWeb}) =>
      web ? (webOverride ?? chord) : chord;

  static String _keyText(ShortcutChord c) => switch (c.key) {
    LogicalKeyboardKey.slash => '/',
    LogicalKeyboardKey.enter => 'Enter',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.home => 'Home',
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    _ => c.key.keyLabel.toUpperCase(),
  };

  /// The text of the corner badge: the letter or digit, with an arrow for Shift chords.
  String get hintLabel => hintLabelFor();

  /// [hintLabel] for the chord in effect on the web or elsewhere ([chordFor]).
  String hintLabelFor({bool web = kIsWeb}) {
    final c = chordFor(web: web);
    return c.shift ? '⇧${_keyText(c)}' : _keyText(c);
  }

  /// The full chord for people, e.g. `Alt+Shift+2` or `Ctrl+K`.
  String describe({bool web = kIsWeb}) {
    final c = chordFor(web: web);
    return [
      switch (c.mod) {
        ChordMod.primary => primaryModifierLabel,
        ChordMod.standard => standardModifierLabel,
        ChordMod.none => null,
      },
      if (c.shift) 'Shift',
      _keyText(c),
    ].whereType<String>().join('+');
  }

  /// The name of the action, in the language of the user.
  String label(AppLocalizations l) => switch (this) {
    back => l.shortcutBack,
    create => l.shortcutCreate,
    home => l.shortcutHome,
    discard => l.shortcutDiscard,
    save => l.shortcutSave,
    confirm => l.shortcutConfirm,
    cancel => l.shortcutCancel,
    find => l.shortcutFind,
    addLine => l.shortcutAddLine,
    nextPage => l.shortcutNextPage,
    search => l.shortcutSearch,
    newTodo => l.shortcutNewTodo,
    kbSearch => l.shortcutKbSearch,
    kbShare => l.shortcutKbShare,
    ticketEscalate => l.collabEscalate,
    ticketDelegate => l.collabDelegate,
    ticketMerge => l.mergeTicket,
    ticketSplit => l.splitTicket,
    palette => l.shortcutPalette,
    selectAll => l.shortcutSelectAll,
    help => l.shortcutHelp,
    tutorialNext => '${l.tutNext} / ${l.tutAssistRun}',
    tutorialBack => l.tutBack,
    tutorialMap => l.tutBackToMap,
    tutorialTakeMe => l.tutTakeMe,
    tutorialPauseOrShowControl => '${l.tutPause} / ${l.tutShowControl}',
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

  /// Whether [key] is an emacs-style editing letter in macOS text fields (with Ctrl).
  static bool macTextKey(LogicalKeyboardKey key) => _macTextKeys.contains(key);

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
      if (c.mod == ChordMod.none) continue;
      if (!c.anyShift && shift != c.shift) continue;
      final keyOk =
          event.logicalKey == c.key ||
          (c.key == LogicalKeyboardKey.enter &&
              event.logicalKey == LogicalKeyboardKey.numpadEnter) ||
          (c.physical != null && event.physicalKey == c.physical);
      if (!keyOk) continue;
      if (c.mod == ChordMod.primary) {
        final ok = isMac ? (ctrl && !alt && !meta) : (alt && !ctrl && !meta);
        if (!ok) continue;
        if (isMac && editing && _macTextKeys.contains(c.key)) continue;
      } else {
        // Ctrl on Windows and Linux, Cmd on macOS.
        final ok = isMac ? (meta && !ctrl && !alt) : (ctrl && !meta && !alt);
        if (!ok) continue;
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

/// Runtime holder for user-customized shortcut bindings loaded from backend preferences.
class ShortcutBindings {
  static final Map<ShortcutAction, ShortcutChord> _overrides = {};

  static ShortcutChord? overrideFor(ShortcutAction action) {
    final chord = _overrides[action];
    if (chord == null) return null;
    if (action != ShortcutAction.cancel && chord.mod == ChordMod.none) {
      return null;
    }
    return chord;
  }

  static bool isCustomized(ShortcutAction action) =>
      overrideFor(action) != null;

  static Map<ShortcutAction, ShortcutChord> get all =>
      Map.unmodifiable(_overrides);

  static void setOverrides(Map<ShortcutAction, ShortcutChord> next) {
    _overrides.clear();
    for (final e in next.entries) {
      if (e.key != ShortcutAction.cancel && e.value.mod == ChordMod.none) {
        continue;
      }
      _overrides[e.key] = e.value;
    }
  }

  /// Exact structural equality between two chords.
  static bool sameChord(ShortcutChord a, ShortcutChord b) =>
      a.mod == b.mod &&
      a.shift == b.shift &&
      a.anyShift == b.anyShift &&
      a.key == b.key;

  /// Whether two chords can match the same key event (accounting for [ShortcutChord.anyShift]).
  static bool chordsOverlap(ShortcutChord a, ShortcutChord b) {
    if (a.mod != b.mod || a.key != b.key) return false;
    if (a.anyShift || b.anyShift) return true;
    return a.shift == b.shift;
  }

  /// Returns the first other [ShortcutAction] whose active chord overlaps with [candidate], or null.
  static ShortcutAction? findConflict(
    ShortcutAction target,
    ShortcutChord candidate, {
    bool web = kIsWeb,
  }) {
    for (final a in ShortcutAction.values) {
      if (a == target) continue;
      if (chordsOverlap(a.chordFor(web: web), candidate)) return a;
    }
    return null;
  }

  static final Map<String, LogicalKeyboardKey> _namedKeys = {
    'keyA': LogicalKeyboardKey.keyA,
    'keyB': LogicalKeyboardKey.keyB,
    'keyC': LogicalKeyboardKey.keyC,
    'keyD': LogicalKeyboardKey.keyD,
    'keyE': LogicalKeyboardKey.keyE,
    'keyF': LogicalKeyboardKey.keyF,
    'keyG': LogicalKeyboardKey.keyG,
    'keyH': LogicalKeyboardKey.keyH,
    'keyI': LogicalKeyboardKey.keyI,
    'keyJ': LogicalKeyboardKey.keyJ,
    'keyK': LogicalKeyboardKey.keyK,
    'keyL': LogicalKeyboardKey.keyL,
    'keyM': LogicalKeyboardKey.keyM,
    'keyN': LogicalKeyboardKey.keyN,
    'keyO': LogicalKeyboardKey.keyO,
    'keyP': LogicalKeyboardKey.keyP,
    'keyQ': LogicalKeyboardKey.keyQ,
    'keyR': LogicalKeyboardKey.keyR,
    'keyS': LogicalKeyboardKey.keyS,
    'keyT': LogicalKeyboardKey.keyT,
    'keyU': LogicalKeyboardKey.keyU,
    'keyV': LogicalKeyboardKey.keyV,
    'keyW': LogicalKeyboardKey.keyW,
    'keyX': LogicalKeyboardKey.keyX,
    'keyY': LogicalKeyboardKey.keyY,
    'keyZ': LogicalKeyboardKey.keyZ,
    'digit0': LogicalKeyboardKey.digit0,
    'digit1': LogicalKeyboardKey.digit1,
    'digit2': LogicalKeyboardKey.digit2,
    'digit3': LogicalKeyboardKey.digit3,
    'digit4': LogicalKeyboardKey.digit4,
    'digit5': LogicalKeyboardKey.digit5,
    'digit6': LogicalKeyboardKey.digit6,
    'digit7': LogicalKeyboardKey.digit7,
    'digit8': LogicalKeyboardKey.digit8,
    'digit9': LogicalKeyboardKey.digit9,
    'enter': LogicalKeyboardKey.enter,
    'escape': LogicalKeyboardKey.escape,
    'slash': LogicalKeyboardKey.slash,
    'space': LogicalKeyboardKey.space,
    'backspace': LogicalKeyboardKey.backspace,
    'tab': LogicalKeyboardKey.tab,
    'f1': LogicalKeyboardKey.f1,
    'f2': LogicalKeyboardKey.f2,
    'f3': LogicalKeyboardKey.f3,
    'f4': LogicalKeyboardKey.f4,
    'f5': LogicalKeyboardKey.f5,
    'f6': LogicalKeyboardKey.f6,
    'f7': LogicalKeyboardKey.f7,
    'f8': LogicalKeyboardKey.f8,
    'f9': LogicalKeyboardKey.f9,
    'f10': LogicalKeyboardKey.f10,
    'f11': LogicalKeyboardKey.f11,
    'f12': LogicalKeyboardKey.f12,
    'home': LogicalKeyboardKey.home,
    'arrowRight': LogicalKeyboardKey.arrowRight,
    'arrowLeft': LogicalKeyboardKey.arrowLeft,
    'arrowUp': LogicalKeyboardKey.arrowUp,
    'arrowDown': LogicalKeyboardKey.arrowDown,
  };

  static final Map<LogicalKeyboardKey, String> _keyToName = {
    for (final e in _namedKeys.entries) e.value: e.key,
  };

  static String keyToName(LogicalKeyboardKey key) =>
      _keyToName[key] ?? '0x${key.keyId.toRadixString(16)}';

  static LogicalKeyboardKey? keyFromName(String name) {
    final named = _namedKeys[name];
    if (named != null) return named;
    if (name.startsWith('0x')) {
      final id = int.tryParse(name.substring(2), radix: 16);
      if (id != null) return LogicalKeyboardKey.findKeyByKeyId(id);
    }
    return null;
  }

  static String modToName(ChordMod mod) => switch (mod) {
    ChordMod.primary => 'primary',
    ChordMod.standard => 'standard',
    ChordMod.none => 'none',
  };

  static ChordMod? modFromName(String name) => switch (name) {
    'primary' => ChordMod.primary,
    'standard' => ChordMod.standard,
    'none' => ChordMod.none,
    _ => null,
  };
}
