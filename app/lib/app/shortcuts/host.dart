import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'actions.dart';
import 'platform.dart';
import 'registry.dart';

/// Listens to the keyboard for the whole app and runs the winning handler of the
/// [ShortcutStack]. Mounted once, in `MaterialApp.builder`, next to the zoom shell.
///
/// Only a key press that a handler took is reported as handled; every other key passes through,
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

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// The window lost the focus (or came back): a key-up may have gone to another window, so the
  /// badges must not stay on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _registry.modifierHeld.value = false;

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

  bool _onKey(KeyEvent e) {
    final kb = HardwareKeyboard.instance;
    _registry.modifierHeld.value = isMac
        ? kb.isControlPressed
        : kb.isAltPressed;
    if (e is KeyUpEvent || _composing) return false;
    final action = ShortcutAction.fromEvent(e, editing: _editable != null);
    if (action == null) return false;
    final handler = _registry.resolve(action);
    if (handler == null) return false;
    // A held key repeats: swallow the repeats, run once.
    if (e is KeyDownEvent) handler();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
