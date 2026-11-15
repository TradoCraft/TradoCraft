import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'actions.dart';
import 'browser_defaults.dart';
import 'button_scan.dart';
import 'key_hint.dart';
import 'platform.dart';
import 'registry.dart';

final _modifierKeys = {
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
};

/// Listens to the keyboard for the whole app and runs the winning handler of the
/// [ShortcutStack]. Mounted once, in `MaterialApp.builder`, next to the zoom shell.
///
/// What it does, in order of priority (ADR 0060):
/// 1. The chords of [ShortcutAction] (Alt chords, Ctrl/Cmd chords): the registered handler of the
///    topmost layer, else for save, confirm, create and find a generic fallback that presses the
///    matching button or focuses the search field of the topmost layer.
/// 2. Alt (Ctrl on macOS) plus a letter: the automatic key of a button of the topmost layer.
/// 3. Enter in a single-line field that does not submit: the next field.
/// 4. After the focused widget has declined the key: Esc (cancel).
///
/// Only a key press that something took is reported as handled; every other key passes through,
/// so typing, Tab and the zoom keys behave as before.
class ShortcutsHost extends ConsumerStatefulWidget {
  /// Creates the host.
  const ShortcutsHost({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  ConsumerState<ShortcutsHost> createState() => _ShortcutsHostState();
}

class _ShortcutsHostState extends ConsumerState<ShortcutsHost>
    with WidgetsBindingObserver {
  late final ShortcutStack _registry = ref.read(shortcutRegistryProvider);
  final _badges = ValueNotifier<List<BadgeSpec>>(const []);

  /// The buttons found when a modifier went down; kept while it is held.
  ScanResult? _scan;

  /// Set when the window lost the focus: a key-up may have gone elsewhere, so no chord counts
  /// until the next modifier event.
  bool _stale = false;
  FocusNode? _rootScope;
  FocusNode? _lastFocus;
  Object? _autofocused;

  /// Whether the last thing the person did was press a key (not click or touch). A number field
  /// that gets the focus from the keyboard is selected whole; one that is clicked keeps the caret.
  bool _byKeyboard = false;

  /// Whether the key event being handled is an auto-repeat of a held key.
  bool _lastKeyRepeated = false;

  @override
  void initState() {
    super.initState();
    BrowserDefaults.install();
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addObserver(this);
    _rootScope = FocusManager.instance.rootScope;
    _rootScope!.onKeyEvent = _onFocusKey;
    FocusManager.instance.addListener(_onFocusChange);
    _registry.addListener(_onRegistry);
  }

  @override
  void dispose() {
    _registry.removeListener(_onRegistry);
    FocusManager.instance.removeListener(_onFocusChange);
    if (_rootScope?.onKeyEvent == _onFocusKey) _rootScope!.onKeyEvent = null;
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _badges.dispose();
    super.dispose();
  }

  /// The window lost the focus (or came back): a key-up may have gone to another window, so the
  /// badges must not stay on and no letter counts until a modifier is pressed again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _stale = true;
    _scan = null;
    _registry.modifierHeld.value = false;
    _registry.standardHeld.value = false;
    _publish(const []);
  }

  /// The focused widget is a text field.
  EditableTextState? get _editable => FocusManager
      .instance
      .primaryFocus
      ?.context
      ?.findAncestorStateOfType<EditableTextState>();

  /// An input method (accents, CJK) is composing text: its keys are not ours.
  bool get _composing {
    final c = _editable?.textEditingValue.composing;
    return c != null && c.isValid && !c.isCollapsed;
  }

  // ---- modifiers and badges ------------------------------------------------------------------

  bool get _primaryHeld {
    final kb = HardwareKeyboard.instance;
    return isMac ? kb.isControlPressed : kb.isAltPressed;
  }

  bool get _standardHeld {
    final kb = HardwareKeyboard.instance;
    return isMac
        ? kb.isMetaPressed && !kb.isControlPressed
        : kb.isControlPressed && !kb.isAltPressed && !kb.isMetaPressed;
  }

  void _syncModifiers() {
    final primary = _primaryHeld, standard = _standardHeld && !_primaryHeld;
    _registry.modifierHeld.value = primary;
    _registry.standardHeld.value = standard;
    if (primary || standard) {
      _refreshBadges();
    } else {
      _scan = null;
      _publish(const []);
    }
  }

  /// A tree walk of the topmost layer; cached while a modifier is held.
  ScanResult _current({bool fresh = false}) {
    final s = _scan;
    // Dispatching a chord looks again: a button may have been enabled or disabled since the scan
    // that the badges use (Save is off while a save runs, and back on while Ctrl is still held).
    if (!fresh && s != null && s.alive) return s;
    return _scan = scanTree(
      context as Element,
      dialogOpen: _registry.hasDialog,
      web: kIsWeb,
    );
  }

  void _refreshBadges({bool rescan = false}) {
    if (rescan) _scan = null;
    final s = _current();
    _publish(
      _primaryHeld
          ? altBadges(s)
          : _standardHeld
          ? standardBadges(s, web: kIsWeb)
          : const [],
    );
  }

  /// Hands the badges to the layer, with rectangles relative to the host.
  void _publish(List<BadgeSpec> global) {
    final box = context.findRenderObject();
    final local = box is RenderBox && box.attached && box.hasSize
        ? [
            for (final b in global)
              BadgeSpec(
                box.globalToLocal(b.rect.topLeft) & b.rect.size,
                b.text,
              ),
          ]
        : const <BadgeSpec>[];
    if (!listEquals(local, _badges.value)) _badges.value = local;
  }

  void _onRegistry() {
    // A popup came or went while a modifier is held: its buttons are the layer now.
    if (_registry.modifierHeld.value || _registry.standardHeld.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_primaryHeld || _standardHeld)) {
          _refreshBadges(rescan: true);
        }
      });
    }
    _autofocusDialog();
  }

  // ---- chords ---------------------------------------------------------------------------------

  bool _onKey(KeyEvent e) {
    if (e is KeyDownEvent) _byKeyboard = true;
    _lastKeyRepeated = e is KeyRepeatEvent;
    final isModifier = _modifierKeys.contains(e.logicalKey);
    if (isModifier) _stale = false;
    if (_stale) return false;
    _syncModifiers();
    if (e is KeyUpEvent || _composing || isModifier) return false;
    final editing = _editable != null;
    final action = ShortcutAction.fromEvent(e, editing: editing);
    if (action != null) {
      final run = _handlerFor(action);
      if (run == null) return false;
      // A held key repeats: swallow the repeats, run once.
      if (e is KeyDownEvent) run();
      BrowserDefaults.markHandled();
      return true;
    }
    // Enter is taken here, not after the focus tree: the app's default shortcuts swallow it there.
    // Only a single-line field that does not submit is affected, see [_enter].
    final kb = HardwareKeyboard.instance;
    if ((e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        _bare(kb)) {
      final took = _enter(e, back: kb.isShiftPressed);
      if (took) BrowserDefaults.markHandled();
      return took;
    }
    return _autoKey(e, editing);
  }

  /// The registered handler, else the generic fallback.
  VoidCallback? _handlerFor(ShortcutAction action) {
    final registered = switch (action) {
      ShortcutAction.find || ShortcutAction.search =>
        _registry.resolve(ShortcutAction.find) ??
            _registry.resolve(ShortcutAction.search),
      _ => _registry.resolve(action),
    };
    if (registered != null) return registered;
    // A dialog layer that has its own scope for the action is asked first (resolve stops there),
    // so what is left is the generic search in the topmost layer.
    switch (action) {
      case ShortcutAction.save:
        return _pressing(() => _current(fresh: true).saveTarget);
      case ShortcutAction.confirm:
        return _pressing(() => _current(fresh: true).confirmTarget);
      case ShortcutAction.create:
        return _pressing(() => _current(fresh: true).createTarget);
      case ShortcutAction.find:
      case ShortcutAction.search:
        final s = _current(fresh: true);
        final field = s.searchFields.firstOrNull;
        if (field == null) return null;
        return () => _focusField(field);
      default:
        return null;
    }
  }

  VoidCallback? _pressing(ScanTarget? Function() find) {
    final t = find();
    final press = t?.onPressed;
    return press == null ? null : () => _press(t!);
  }

  void _press(ScanTarget t) {
    t.press();
    // The press may change the screen: look again, once the frame is through.
    _scan = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncModifiers();
    });
  }

  void _focusField(Element editableOrField) {
    final es = editableOrField is StatefulElement &&
            editableOrField.state is EditableTextState
        ? editableOrField.state as EditableTextState
        : _findEditable(editableOrField);
    if (es == null) return;
    es.widget.focusNode.requestFocus();
    es.widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: es.widget.controller.text.length,
    );
  }

  EditableTextState? _findEditable(Element root) {
    EditableTextState? found;
    void visit(Element e) {
      if (found != null) return;
      if (e is StatefulElement && e.state is EditableTextState) {
        found = e.state as EditableTextState;
        return;
      }
      e.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  /// Alt (Ctrl on macOS) with a letter presses the button holding that letter.
  bool _autoKey(KeyEvent e, bool editing) {
    final kb = HardwareKeyboard.instance;
    if (kb.isShiftPressed || kb.isMetaPressed) return false;
    final ok = isMac
        ? kb.isControlPressed && !kb.isAltPressed
        : kb.isAltPressed && !kb.isControlPressed;
    final label = e.logicalKey.keyLabel;
    if (!ok || label.length != 1) return false;
    final letter = label.toLowerCase();
    if (letter.codeUnitAt(0) < 97 || letter.codeUnitAt(0) > 122) return false;
    if (isMac && editing && ShortcutAction.macTextKey(e.logicalKey)) {
      return false;
    }
    final target = _current().byLetter[letter];
    if (target == null || target.onPressed == null) return false;
    if (e is KeyDownEvent) _press(target);
    BrowserDefaults.markHandled();
    return true;
  }

  // ---- keys the focused widget did not take ------------------------------------------------

  static bool _bare(HardwareKeyboard kb) =>
      !kb.isControlPressed &&
      !kb.isAltPressed &&
      !kb.isMetaPressed;

  KeyEventResult _onFocusKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent || _composing) return KeyEventResult.ignored;
    final kb = HardwareKeyboard.instance;
    if (!_bare(kb)) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape && !kb.isShiftPressed) {
      return _escape(e) ? KeyEventResult.handled : KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  /// Esc: the registered cancel handler of the topmost layer; in a dialog its Cancel or Close
  /// button, else the dialog's own pop (which a `PopScope` can veto); on a page its Cancel button.
  bool _escape(KeyEvent e) {
    final run = _escapeAction();
    if (run == null) return false;
    if (e is KeyDownEvent) run();
    BrowserDefaults.markHandled();
    return true;
  }

  /// What Esc does right now, or null when there is nothing for it to do.
  VoidCallback? _escapeAction() {
    final handler = _registry.resolve(ShortcutAction.cancel);
    if (handler != null) return handler;
    final s = _current(fresh: true);
    final cancel = s.cancelTarget;
    if (cancel != null && cancel.onPressed != null) return () => _press(cancel);
    final popup = s.popup;
    if (popup != null && popup.barrierDismissible && popup.isCurrent) {
      return () => popup.navigator?.maybePop();
    }
    return null;
  }

  /// Enter in a single-line field that does not submit moves to the next field, Shift+Enter back.
  bool _enter(KeyEvent e, {required bool back}) {
    final es = _editable;
    if (es == null) return false;
    final w = es.widget;
    final action = w.textInputAction;
    if (w.maxLines != 1 ||
        w.readOnly ||
        w.onSubmitted != null ||
        w.onEditingComplete != null ||
        w.keyboardType == TextInputType.multiline ||
        (action != null &&
            action != TextInputAction.done &&
            action != TextInputAction.next &&
            action != TextInputAction.previous)) {
      return false;
    }
    if (e is KeyDownEvent) {
      final focus = FocusManager.instance.primaryFocus!;
      // The text input also reports this Enter to the field as its action "done", which unfocuses
      // the field it is delivered to. Moving the focus right now would let that "done" land on the
      // new field and leave nothing focused (seen in Firefox), so the move waits until the frame is
      // through and the old field has had it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || focus.context == null) return;
        // The next field, not the next control: the buttons between the fields are skipped. After
        // the last field the ordinary traversal goes on (to Save, for instance).
        if (!_moveToField(focus, back: back)) {
          back ? focus.previousFocus() : focus.nextFocus();
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }
    return true;
  }

  /// Moves to the next (previous) editable field of the focus scope in reading order; false when
  /// there is none.
  bool _moveToField(FocusNode from, {required bool back}) {
    final scope = from.nearestScope;
    if (scope == null) return false;
    final fields = _readingOrder([
      for (final n in scope.traversalDescendants)
        if (n.canRequestFocus && _isEditable(n)) n,
    ]);
    final i = fields.indexOf(from);
    final j = back ? i - 1 : i + 1;
    if (i < 0 || j < 0 || j >= fields.length) return false;
    final to = fields[j];
    to.requestFocus();
    final c = to.context;
    if (c != null) Scrollable.ensureVisible(c, duration: Duration.zero);
    return true;
  }

  static bool _isEditable(FocusNode n) {
    final es = n.context?.findAncestorStateOfType<EditableTextState>();
    return es != null && !es.widget.readOnly;
  }

  /// Top to bottom, and left to right within a line.
  static List<FocusNode> _readingOrder(List<FocusNode> nodes) {
    nodes.sort((a, b) {
      final c = a.rect.center.dy.compareTo(b.rect.center.dy);
      return c != 0 ? c : a.rect.center.dx.compareTo(b.rect.center.dx);
    });
    final rows = <List<FocusNode>>[];
    for (final n in nodes) {
      if (rows.isNotEmpty) {
        final last = rows.last.first.rect;
        if ((n.rect.center.dy - last.center.dy).abs() <
            math.min(n.rect.height, last.height) / 2) {
          rows.last.add(n);
          continue;
        }
      }
      rows.add([n]);
    }
    return [
      for (final r in rows)
        ...(r..sort((a, b) => a.rect.center.dx.compareTo(b.rect.center.dx))),
    ];
  }

  // ---- focus ----------------------------------------------------------------------------------

  void _onFocusChange() {
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _lastFocus)) return;
    _lastFocus = node;
    final es = node?.context?.findAncestorStateOfType<EditableTextState>();
    if (es == null) return;
    // A number or amount field reached with the keyboard is selected whole, so typing replaces it.
    // (A click keeps the caret where it landed; a mouse also puts the focus highlight in the
    // keyboard mode, so that mode cannot tell the two apart.)
    if (!_byKeyboard) return;
    if (es.widget.keyboardType.index != TextInputType.number.index) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || FocusManager.instance.primaryFocus != node) return;
      final c = es.widget.controller;
      if (c.text.isNotEmpty) {
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// A dialog or sheet that has text fields opens with the cursor in the first of them, unless
  /// one of its fields already took the focus (`autofocus`).
  void _autofocusDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_registry.hasDialog) {
        _autofocused = null;
        return;
      }
      // The editable fields of current popup routes, in tree order; the last route is on top.
      final fields = <(ModalRoute<dynamic>, EditableTextState)>[];
      void visit(Element e) {
        final w = e.widget;
        if (w is Offstage && w.offstage) return;
        if (w is TickerMode && !w.enabled) return;
        if (e is StatefulElement && e.state is EditableTextState) {
          final r = ModalRoute.of(e);
          if (r is PopupRoute && r.isCurrent && r.isActive) {
            fields.add((r, e.state as EditableTextState));
          }
          return;
        }
        e.visitChildren(visit);
      }

      visit(context as Element);
      if (fields.isEmpty) return;
      final route = fields.last.$1;
      if (identical(route, _autofocused)) return;
      _autofocused = route;
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.context?.findAncestorStateOfType<EditableTextState>() !=
              null ||
          fields.any((f) => f.$1 == route && f.$2.widget.autofocus)) {
        return;
      }
      fields
          .where((f) => f.$1 == route && !f.$2.widget.readOnly)
          .firstOrNull
          ?.$2
          .widget
          .focusNode
          .requestFocus();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topLeft,
      fit: StackFit.passthrough,
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (_) {
            // Badges follow what scrolls underneath them.
            if (_badges.value.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && (_primaryHeld || _standardHeld)) {
                  _refreshBadges();
                }
              });
            }
            return false;
          },
          // While a widget has the focus, Esc never reaches the root focus node: the app's shortcuts
          // turn it into the framework's "dismiss" intent, which a text field answers itself (it
          // only hides its toolbar) and never forwards to the action of an ancestor. So the host
          // has an Esc shortcut of its own. It sits outside the navigator, so anything inside the
          // page that handles Esc itself (a menu, a list of suggestions) is closer and goes first.
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): _EscapeIntent(),
            },
            child: Actions(
              actions: {_EscapeIntent: _EscapeAction(this)},
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => _byKeyboard = false,
                child: widget.child,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: ValueListenableBuilder<List<BadgeSpec>>(
                valueListenable: _badges,
                builder: (context, specs, _) => _BadgeLayer(
                  specs: specs,
                  standard: _registry.standardHeld.value,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The Esc key of the host (see [ShortcutAction.cancel]).
class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

/// Runs what Esc does now; enabled only when there is something for it to do, so otherwise the
/// key goes on to the rest of the app.
class _EscapeAction extends Action<_EscapeIntent> {
  _EscapeAction(this._host);
  final _ShortcutsHostState _host;

  @override
  bool isEnabled(_EscapeIntent intent) =>
      !_host._composing && _host._escapeAction() != null;

  @override
  Object? invoke(_EscapeIntent intent) {
    BrowserDefaults.markHandled();
    // A held key repeats: Esc runs once.
    if (_host._lastKeyRepeated) return null;
    _host._escapeAction()?.call();
    return null;
  }
}

/// Draws the badges at the rectangles of their buttons, above the app.
class _BadgeLayer extends StatelessWidget {
  const _BadgeLayer({required this.specs, required this.standard});
  final List<BadgeSpec> specs;
  final bool standard;

  @override
  Widget build(BuildContext context) {
    if (specs.isEmpty) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.topLeft,
      clipBehavior: Clip.none,
      children: [
        for (final s in specs)
          Positioned(
            left: s.rect.right,
            top: s.rect.top - 6,
            child: FractionalTranslation(
              translation: const Offset(-0.7, 0),
              child: KeyBadge(
                s.text,
                badgeKey: standard
                    ? const ValueKey('std-key-badge')
                    : const ValueKey('auto-key-badge'),
              ),
            ),
          ),
      ],
    );
  }
}
