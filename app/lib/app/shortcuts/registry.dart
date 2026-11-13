import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../workspace.dart';
import 'actions.dart';

/// Where a scope sits. A higher layer wins over a lower one; the newest scope wins within a layer.
enum ShortcutLayer {
  /// The navigation frame (menu digits, Home).
  shell,

  /// A screen: the main area or the active tab.
  page,

  /// A dialog or sheet. It is modal: shortcuts it does not handle are not passed to lower layers.
  dialog,
}

/// What the scopes currently offer, and which of them wins (topmost dialog, then the active tab,
/// then the shell). Handlers register and unregister with their widget's lifecycle.
class ShortcutStack extends ChangeNotifier {
  /// True while the primary modifier is held; badges ([KeyHint]) show only then.
  final modifierHeld = ValueNotifier<bool>(false);

  final _entries = <Object, _Entry>{};
  int _seq = 0;
  bool _notifyQueued = false;
  bool _disposed = false;

  /// Adds a scope; returns the token for [update] and [unregister].
  Object register(
    ShortcutLayer layer,
    Map<ShortcutAction, VoidCallback?> handlers,
  ) {
    final token = Object();
    _entries[token] = _Entry(layer, _seq++, handlers);
    _changed();
    return token;
  }

  /// Replaces the handlers of a scope (on every build of its widget).
  void update(Object token, Map<ShortcutAction, VoidCallback?> handlers) {
    final e = _entries[token];
    if (e == null) return;
    final before = e.enabled;
    e.handlers = handlers;
    if (!setEquals(before, e.enabled)) _changed();
  }

  /// Removes a scope.
  void unregister(Object token) {
    if (_entries.remove(token) != null) _changed();
  }

  /// The handler that wins for [action], or null when none is enabled. Scopes are asked from the
  /// top; a dialog stops the search.
  VoidCallback? resolve(ShortcutAction action) {
    final list = _entries.values.toList()
      ..sort((a, b) {
        final c = b.layer.index.compareTo(a.layer.index);
        return c != 0 ? c : b.seq.compareTo(a.seq);
      });
    for (final e in list) {
      final h = e.handlers[action];
      if (h != null) return h;
      if (e.layer == ShortcutLayer.dialog) return null;
    }
    return null;
  }

  /// Whether [action] would do something now.
  bool isEnabled(ShortcutAction action) => resolve(action) != null;

  // Registrations happen while building; listeners are told right after.
  void _changed() {
    if (_notifyQueued) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    modifierHeld.dispose();
    super.dispose();
  }
}

class _Entry {
  _Entry(this.layer, this.seq, this.handlers);
  final ShortcutLayer layer;
  final int seq;
  Map<ShortcutAction, VoidCallback?> handlers;

  Set<ShortcutAction> get enabled => {
    for (final e in handlers.entries)
      if (e.value != null) e.key,
  };
}

/// Makes every dialog, bottom sheet, picker and popup menu modal for shortcuts: while such a route
/// is open on the observed navigator, an empty [ShortcutLayer.dialog] scope sits in the stack, so
/// the shell and page handlers (menu digits, Home, Back, Save) are not reached. A dialog that
/// wants keys of its own adds a [ShortcutScope] on the dialog layer, which is newer and wins.
/// Use one observer per navigator (root router, shell route, each workspace tab): popups opened
/// with `useRootNavigator: false` (bottom sheets, menus) land on the nearest navigator, not the
/// root. They all share the stack, and each route holds its own scope, so shortcuts stay blocked
/// until every open popup, on any navigator, is closed.
class ModalShortcutObserver extends NavigatorObserver {
  /// Creates the observer for [stack].
  ModalShortcutObserver(this.stack);

  /// The stack that gets the blocking scopes.
  final ShortcutStack stack;
  final _tokens = <Route<dynamic>, Object>{};

  void _add(Route<dynamic> r) {
    if (r is PopupRoute && !_tokens.containsKey(r)) {
      _tokens[r] = stack.register(ShortcutLayer.dialog, const {});
    }
  }

  /// Releases the scopes of popups still open when the navigator goes away (a tab is closed).
  void dispose() {
    for (final t in _tokens.values) {
      stack.unregister(t);
    }
    _tokens.clear();
  }

  void _remove(Route<dynamic>? r) {
    final t = _tokens.remove(r);
    if (t != null) stack.unregister(t);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    if (newRoute != null) _add(newRoute);
  }
}

/// The registry of the running app.
final shortcutRegistryProvider = Provider<ShortcutStack>((ref) {
  final r = ShortcutStack();
  ref.onDispose(r.dispose);
  return r;
});

/// Tells [ShortcutScope]s below whether their screen is the visible one (the main area is not
/// while a tab is focused). Absent means active.
class ShortcutActivity extends InheritedWidget {
  /// Creates the marker.
  const ShortcutActivity({
    super.key,
    required this.active,
    required super.child,
  });

  /// Whether scopes below take part.
  final bool active;

  /// The nearest marker's value; true when there is none.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShortcutActivity>()?.active ??
      true;

  @override
  bool updateShouldNotify(ShortcutActivity old) => active != old.active;
}

/// Offers keyboard shortcuts while it is mounted and visible: [actions] maps an action to what it
/// does, null (or a missing entry) meaning "not available now". Inside the workspace only the
/// focused tab takes part (`TabScope.activeOf`); a dialog uses [ShortcutLayer.dialog].
class ShortcutScope extends ConsumerStatefulWidget {
  /// Creates a scope.
  const ShortcutScope({
    super.key,
    required this.actions,
    required this.child,
    this.layer = ShortcutLayer.page,
  });

  /// What each action does here.
  final Map<ShortcutAction, VoidCallback?> actions;

  /// The layer of the scope.
  final ShortcutLayer layer;

  /// The screen.
  final Widget child;

  @override
  ConsumerState<ShortcutScope> createState() => _ShortcutScopeState();
}

class _ShortcutScopeState extends ConsumerState<ShortcutScope> {
  late final ShortcutStack _registry = ref.read(shortcutRegistryProvider);
  Object? _token;

  void _sync(bool active) {
    if (!active) {
      _drop();
    } else if (_token == null) {
      _token = _registry.register(widget.layer, widget.actions);
    } else {
      _registry.update(_token!, widget.actions);
    }
  }

  void _drop() {
    final t = _token;
    if (t != null) _registry.unregister(t);
    _token = null;
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A dialog is modal wherever it was opened from: it never depends on the visibility of a tab.
    _sync(
      widget.layer == ShortcutLayer.dialog ||
          (TabScope.activeOf(context) && ShortcutActivity.of(context)),
    );
    return widget.child;
  }
}
