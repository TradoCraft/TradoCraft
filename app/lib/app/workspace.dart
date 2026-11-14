import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/field/offline/kv_store.dart';
import '../l10n/l10n.dart';
import '../shared/app_icons.dart';
import 'detail_routes.dart';
import 'shortcuts/actions.dart';
import 'shortcuts/registry.dart';

/// One open tab of the workspace: a detail screen (ticket, quotation, ...) identified by its
/// location. Tabs keep their screens alive, so an unsent reply or a half-edited quote is still
/// there when you come back to the tab.
class WorkTab {
  /// Creates a tab for [location].
  const WorkTab({required this.id, required this.location, this.title});

  /// Unique among the open tabs; never reused.
  final int id;

  /// The location of the screen on top of the tab's own navigation stack.
  final String location;

  /// Set by the screen once it knows (a ticket number); until then the label comes from the location.
  final String? title;

  /// A copy with the given location and/or title replaced.
  WorkTab copyWith({String? location, String? title}) => WorkTab(
    id: id,
    location: location ?? this.location,
    title: title ?? this.title,
  );
}

/// The open tabs and which of them is focused.
class WorkspaceState {
  const WorkspaceState({this.tabs = const [], this.active});

  final List<WorkTab> tabs;

  /// The id of the focused tab; null = the main area (lists and settings).
  final int? active;

  /// The focused tab; null when the main area is shown.
  WorkTab? get activeTab {
    for (final t in tabs) {
      if (t.id == active) return t;
    }
    return null;
  }

  /// Position in the stack: 0 is the main area, tabs follow.
  int get stackIndex {
    final i = tabs.indexWhere((t) => t.id == active);
    return i < 0 ? 0 : i + 1;
  }
}

/// The open tabs of the signed-in user, kept per profile (the storage is the profile's own) and
/// restored on start. Only locations and titles are stored, not the screens' state.
class WorkspaceNotifier extends Notifier<WorkspaceState> {
  static const storageKey = 'workspace.tabs';

  int _next = 1;
  final _dirty = <int, ValueNotifier<bool>>{};
  Timer? _backgroundTimer;
  bool _backgroundNext = false;

  /// The last location shown in the main area; where a detail link that was only opened as a
  /// tab returns the main area to.
  String homeLocation = '';

  @override
  WorkspaceState build() {
    final store = ref.watch(userKvStoreProvider);
    ref.onDispose(() => _backgroundTimer?.cancel());
    // A new store (another user or environment): a restore still running for the old one is void.
    _restore(store, ++_generation);
    return const WorkspaceState();
  }

  /// Bumped whenever the workspace is reset or changes store, so that a restore that was started
  /// earlier and finishes later cannot reopen tabs of the previous session.
  int _generation = 0;

  /// Reopens the tabs saved in [store]; unreadable data is ignored. [generation] is the value of
  /// [_generation] when the restore began; if it has moved on, the result is dropped.
  Future<void> _restore(KvStore store, int generation) async {
    try {
      final raw = await store.get(storageKey);
      if (raw == null ||
          !ref.mounted ||
          generation != _generation ||
          state.tabs.isNotEmpty) {
        return;
      }
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final tabs = <WorkTab>[
        for (final t in (json['tabs'] as List? ?? const []))
          if (t is Map &&
              t['l'] is String &&
              isDetailLocation(t['l'] as String))
            WorkTab(
              id: _next++,
              location: t['l'] as String,
              title: t['t'] as String?,
            ),
      ];
      final a = json['active'];
      state = WorkspaceState(
        tabs: tabs,
        active: a is int && a >= 0 && a < tabs.length ? tabs[a].id : null,
      );
    } catch (_) {
      // An unreadable list of tabs is not worth an error: start without tabs.
    }
  }

  /// Stores the open tabs in the user's storage.
  void _save() {
    final s = state;
    ref
        .read(userKvStoreProvider)
        .set(
          storageKey,
          jsonEncode({
            'tabs': [
              for (final t in s.tabs) {'l': t.location, 't': t.title},
            ],
            'active': s.tabs.indexWhere((t) => t.id == s.active),
          }),
        )
        .catchError((Object _) {});
  }

  /// Replaces the state and stores it.
  void _set(WorkspaceState s) {
    state = s;
    _save();
  }

  /// Opens [location] in a tab, or focuses the tab that already shows it. With
  /// `focus: false` the tab opens in the background. Returns the tab's id.
  int open(String location, {bool focus = true}) {
    // A new record has no identity yet: each "new" location gets its own tab.
    final isNew = Uri.parse(location).pathSegments.lastOrNull == 'new';
    final existing = isNew
        ? const <WorkTab>[]
        : state.tabs.where((t) => t.location == location);
    if (existing.isNotEmpty) {
      final id = existing.first.id;
      if (focus) _set(WorkspaceState(tabs: state.tabs, active: id));
      return id;
    }
    final tab = WorkTab(id: _next++, location: location);
    _set(
      WorkspaceState(
        tabs: [...state.tabs, tab],
        active: focus ? tab.id : state.active,
      ),
    );
    return tab.id;
  }

  /// Focuses the tab [id]; does nothing for an unknown id.
  void focus(int id) {
    if (state.tabs.any((t) => t.id == id) && state.active != id) {
      _set(WorkspaceState(tabs: state.tabs, active: id));
    }
  }

  /// Shows the main area again (the tabs stay open).
  void focusHome() {
    if (state.active != null) _set(WorkspaceState(tabs: state.tabs));
  }

  /// Closes a tab without asking; use [requestClose] for the unsaved-changes check.
  void close(int id) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final tabs = [...state.tabs]..removeAt(i);
    _dirty.remove(id);
    int? active = state.active;
    if (active == id) {
      active = tabs.isEmpty ? null : tabs[i.clamp(0, tabs.length - 1)].id;
    }
    _set(WorkspaceState(tabs: tabs, active: active));
  }

  /// Closes every tab without asking (switching environment: the tabs belong to the old one).
  void closeAll() {
    _generation++; // a restore still reading the old store must not bring tabs back
    _dirty.clear();
    _set(const WorkspaceState());
  }

  /// Sets the label title the screen of tab [id] reported.
  void setTitle(int id, String title) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0 || state.tabs[i].title == title) return;
    final tabs = [...state.tabs];
    tabs[i] = tabs[i].copyWith(title: title);
    _set(WorkspaceState(tabs: tabs, active: state.active));
  }

  /// Records the location now on top of tab [id]'s own navigation stack.
  void setLocation(int id, String location) {
    final i = state.tabs.indexWhere((t) => t.id == id);
    if (i < 0 || state.tabs[i].location == location) return;
    final tabs = [...state.tabs];
    tabs[i] = tabs[i].copyWith(location: location);
    _set(WorkspaceState(tabs: tabs, active: state.active));
  }

  /// Whether the tab holds edits that are not saved; the screen sets it.
  ValueNotifier<bool> dirtyOf(int id) =>
      _dirty.putIfAbsent(id, () => ValueNotifier(false));

  /// Whether tab [id] currently holds unsaved edits.
  bool isDirty(int id) => _dirty[id]?.value ?? false;

  /// How many open tabs hold unsaved edits.
  int get dirtyCount =>
      state.tabs.where((t) => _dirty[t.id]?.value ?? false).length;

  /// A ctrl-click on a list row is about to open that row: open it in the background.
  void backgroundNextOpen() {
    _backgroundNext = true;
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer(
      const Duration(milliseconds: 600),
      () => _backgroundNext = false,
    );
  }

  /// Reads and clears the flag set by [backgroundNextOpen].
  bool takeBackgroundFlag() {
    final v = _backgroundNext;
    _backgroundNext = false;
    return v;
  }
}

/// How a detail location becomes a screen; tests replace it with simple screens.
final detailScreenProvider = Provider<Widget? Function(Uri uri)>(
  (ref) => detailScreen,
);

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceState>(
  WorkspaceNotifier.new,
);

/// Closes a tab, asking first when it has unsaved edits. Returns whether the tab was closed
/// (false when the user kept it open).
Future<bool> requestCloseTab(
  BuildContext context,
  WidgetRef ref,
  int id,
) async {
  final n = ref.read(workspaceProvider.notifier);
  if (n.isDirty(id)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.l10n.unsavedChangesTitle),
        content: Text(c.l10n.unsavedChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.l10n.discardChanges),
          ),
        ],
      ),
    );
    if (ok != true) return false;
  }
  n.close(id);
  return true;
}

/// What a screen inside a tab can know about its tab.
class TabScope extends InheritedWidget {
  const TabScope({
    super.key,
    required this.id,
    required this.active,
    required this.dirty,
    required this.setTitle,
    required super.child,
  });

  /// The tab this scope belongs to.
  final int id;

  /// Whether the tab is the focused one.
  final bool active;

  /// Set to true while the screen holds unsaved edits.
  final ValueNotifier<bool> dirty;
  final void Function(String title) setTitle;

  /// The scope of the enclosing tab, or null outside the workspace.
  static TabScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TabScope>();

  /// Tells the tab a title for its label (a ticket number); does nothing outside a tab.
  static void reportTitle(BuildContext context, String title) {
    final scope = context.getInheritedWidgetOfExactType<TabScope>();
    if (scope == null || title.isEmpty) return;
    // Screens report from load callbacks, possibly inside a frame: apply after it.
    scheduleMicrotask(() => scope.setTitle(title));
  }

  /// Marks the tab as holding unsaved edits (or not); does nothing outside a tab.
  static void reportDirty(BuildContext context, bool dirty) {
    final scope = context.getInheritedWidgetOfExactType<TabScope>();
    if (scope != null && scope.dirty.value != dirty) scope.dirty.value = dirty;
  }

  /// Whether the screen is visible: true outside the workspace and in the focused tab. Screens
  /// that poll pause while it is false.
  static bool activeOf(BuildContext context) =>
      maybeOf(context)?.active ?? true;

  @override
  bool updateShouldNotify(TabScope old) => active != old.active;
}

/// Detail prefixes whose section list lives under another path (`/suppliers/..` is in Purchasing).
const _sectionOfPrefix = {
  'suppliers': 'purchasing',
  'supplier-invoices': 'finance',
};

/// The section list a detail [location] belongs to, e.g. `/orders/x` -> `/orders`.
String sectionOfDetail(String location) {
  final first = Uri.parse(location).pathSegments.first;
  return '/${_sectionOfPrefix[first] ?? first}';
}

/// The page that a detail location shows in the main area's router: it hands the location to
/// the workspace (open or focus its tab) and removes itself again. That keeps every
/// `context.push('/orders/..')` and `context.go('/helpdesk/..')` of the lists working unchanged.
class DetailPortal extends ConsumerStatefulWidget {
  const DetailPortal({super.key, required this.location});
  final String location;

  @override
  ConsumerState<DetailPortal> createState() => _DetailPortalState();
}

class _DetailPortalState extends ConsumerState<DetailPortal> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final n = ref.read(workspaceProvider.notifier);
      n.open(widget.location, focus: !n.takeBackgroundFlag());
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
      } else {
        final home = n.homeLocation;
        router.go(home.isNotEmpty ? home : sectionOfDetail(widget.location));
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// A [GoRouter] stand-in for the screens of one tab, so that their `context.push`, `context.go`,
/// `context.pop(result)` and `context.canPop()` act on the tab's own navigator: a quotation
/// opened from a ticket stays in the ticket's tab and returns its result there. Going to a
/// section list (the usual "back" when nothing is left to pop) closes the tab and shows the list.
class TabRouter implements GoRouter {
  TabRouter({
    required this.navigator,
    required this.leaveToMainArea,
    this.screenFor = detailScreen,
  });

  /// Builds the screen of a detail location; replaced in tests.
  final Widget? Function(Uri uri) screenFor;

  final GlobalKey<NavigatorState> navigator;

  /// Called with a non-detail location: close this tab and show that location in the main area.
  final void Function(String location) leaveToMainArea;

  NavigatorState get _nav => navigator.currentState!;

  /// The route that shows [location] in the tab's navigator; null for a non-detail location.
  Route<T>? route<T>(String location) {
    final screen = screenFor(Uri.parse(location));
    if (screen == null) return null;
    return MaterialPageRoute<T>(
      settings: RouteSettings(name: location),
      builder: (_) => screen,
    );
  }

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) {
    final r = route<T>(location);
    if (r == null) {
      leaveToMainArea(location);
      return Future.value();
    }
    return _nav.push(r);
  }

  @override
  void go(String location, {Object? extra}) {
    final r = route<Object?>(location);
    if (r == null) {
      leaveToMainArea(location);
    } else {
      _nav.pushAndRemoveUntil(r, (_) => false);
    }
  }

  @override
  Future<T?> pushReplacement<T extends Object?>(
    String location, {
    Object? extra,
  }) {
    final r = route<T>(location);
    if (r == null) {
      leaveToMainArea(location);
      return Future.value();
    }
    return _nav.pushReplacement<T, Object?>(r);
  }

  @override
  Future<T?> replace<T>(String location, {Object? extra}) {
    final r = route<T>(location);
    if (r == null) {
      leaveToMainArea(location);
      return Future.value();
    }
    return _nav.pushReplacement<T, Object?>(r);
  }

  @override
  void pop<T extends Object?>([T? result]) {
    if (_nav.canPop()) _nav.pop(result);
  }

  @override
  bool canPop() => navigator.currentState?.canPop() ?? false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Follows the routes of one tab's navigator and reports the location of the one on top. Routes
/// are tracked by identity, so a removal or replacement of a route below the top is handled.
class _TabObserver extends NavigatorObserver {
  _TabObserver(this.onLocation);
  final void Function(String location) onLocation;
  final _stack = <Route<dynamic>>[];

  void _report() {
    if (_stack.isNotEmpty) onLocation(_stack.last.settings.name ?? '');
  }

  // Only screens have a location. A bottom sheet or a menu opened inside the tab lands on the
  // same navigator but has no name: it must not replace the tab's location (which would make the
  // shell lose the section, and the to-do context the record).
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute) return;
    _stack.add(route);
    _report();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _report();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _report();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0) {
      if (newRoute == null) {
        _stack.removeAt(i);
      } else {
        _stack[i] = newRoute;
      }
    } else if (newRoute is PageRoute) {
      _stack.add(newRoute);
    }
    _report();
  }
}

/// The body of the shell: the main area and the open tabs, one navigator each, all kept alive
/// (only the focused one is visible and ticking).
class WorkspaceBody extends ConsumerWidget {
  const WorkspaceBody({super.key, required this.home, required this.wide});

  /// The main area: the router's current page (lists, settings).
  final Widget home;

  /// Wide layouts show a tab strip; narrow ones use [WorkspaceMenuButton] in the app bar.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    final root = GoRouter.of(context);
    return Column(
      children: [
        if (wide && ws.tabs.isNotEmpty) const WorkspaceTabStrip(),
        Expanded(
          child: IndexedStack(
            index: ws.stackIndex,
            sizing: StackFit.expand,
            children: [
              ShortcutActivity(
                active: ws.active == null,
                child: ExcludeFocus(
                  excluding: ws.active != null,
                  child: TickerMode(enabled: ws.active == null, child: home),
                ),
              ),
              for (final t in ws.tabs)
                _TabHost(
                  key: ValueKey(t.id),
                  tab: t,
                  active: t.id == ws.active,
                  root: root,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hosts one tab: its own navigator, kept alive while the tab is open.
class _TabHost extends ConsumerStatefulWidget {
  const _TabHost({
    super.key,
    required this.tab,
    required this.active,
    required this.root,
  });

  final WorkTab tab;
  final bool active;
  final GoRouter root;

  @override
  ConsumerState<_TabHost> createState() => _TabHostState();
}

class _TabHostState extends ConsumerState<_TabHost> {
  final _navigator = GlobalKey<NavigatorState>();
  late final String _initial = widget.tab.location;
  late final TabRouter _router = TabRouter(
    navigator: _navigator,
    leaveToMainArea: _leave,
    screenFor: ref.read(detailScreenProvider),
  );
  late final _TabObserver _observer = _TabObserver(_located);
  // Menus and bottom sheets opened inside the tab land on its navigator: keep shortcuts blocked.
  late final ModalShortcutObserver _modal = ModalShortcutObserver(
    ref.read(shortcutRegistryProvider),
  );

  @override
  void initState() {
    super.initState();
    _modal; // created now: ref is not usable in dispose
  }

  @override
  void dispose() {
    _modal.dispose();
    super.dispose();
  }

  // A tab restored in the background builds its screen only when first shown.
  late bool _built = widget.active;

  int get _id => widget.tab.id;

  /// Whether the tab's navigator has a screen below the top one (the Back shortcut works).
  bool _canPop = false;

  /// Passes the location now shown by this tab on to the workspace.
  void _located(String location) {
    // Navigation callbacks can run while the tree is building.
    scheduleMicrotask(() {
      if (mounted) {
        final can = _navigator.currentState?.canPop() ?? false;
        if (can != _canPop) setState(() => _canPop = can);
        ref.read(workspaceProvider.notifier).setLocation(_id, location);
      }
    });
  }

  /// Leaves this tab for a location of the main area. Unsaved edits are confirmed first (as with
  /// the close button); when the user keeps the tab, nothing else happens.
  Future<void> _leave(String location) async {
    final n = ref.read(workspaceProvider.notifier);
    final root = widget.root;
    final closed = await requestCloseTab(context, ref, _id);
    if (!closed) return;
    n.focusHome();
    root.go(location);
  }

  @override
  void didUpdateWidget(_TabHost old) {
    super.didUpdateWidget(old);
    if (widget.active) _built = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_built) return const SizedBox.shrink();
    final n = ref.read(workspaceProvider.notifier);
    return TabScope(
      id: _id,
      active: widget.active,
      dirty: n.dirtyOf(_id),
      setTitle: (t) => n.setTitle(_id, t),
      // Back pops the tab's route; at the tab's first screen it is not offered (no badge either).
      child: ShortcutScope(
        actions: {
          ShortcutAction.back: _canPop
              ? () => _navigator.currentState?.maybePop()
              : null,
        },
        child: InheritedGoRouter(
          goRouter: _router,
          child: ExcludeFocus(
            excluding: !widget.active,
            child: TickerMode(
              enabled: widget.active,
              // A semantic boundary: the modal barrier of the tab's page route blocks the semantics of
              // everything painted before it, and without a boundary around the navigator that
              // reaches up to the navigation rail, the tab strip and the banner, which then vanish
              // from the accessibility tree (screen readers could not reach them from a record).
              child: Semantics(
                container: true,
                explicitChildNodes: true,
                child: Navigator(
                  key: _navigator,
                  observers: [_observer, _modal],
                  onGenerateInitialRoutes: (_, _) => [
                    _router.route<Object?>(_initial) ??
                        MaterialPageRoute<Object?>(
                          builder: (_) => const SizedBox(),
                        ),
                  ],
                  onGenerateRoute: (s) => _router.route<Object?>(s.name ?? ''),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The label of a tab: the title its screen reported, or the kind and the start of the id.
String tabLabel(AppLocalizations l, WorkTab tab) {
  if (tab.title != null && tab.title!.isNotEmpty) return tab.title!;
  final uri = Uri.parse(tab.location);
  final s = uri.pathSegments;
  final last = s.isEmpty ? '' : s.last;
  final short = last.length > 8 ? last.substring(0, 8) : last;
  final kind = switch (s.isEmpty ? '' : s.first) {
    'helpdesk' => l.tabTicket,
    'quotations' => last == 'new' ? l.tabNewQuotation : l.tabQuotation,
    'orders' => l.tabOrder,
    'repairs' => l.tabRepair,
    'jobs' => s.length == 3 ? l.tabContract : l.tabJob,
    'customers' => l.tabCustomer,
    'products' => l.tabProduct,
    'opportunities' => l.tabOpportunity,
    'stock' => s.length > 1 && s[1] == 'counts' ? l.tabCount : l.tabStock,
    'kb' => l.tabArticle,
    'production' => l.tabProductionOrder,
    'delivery' => l.tabDeliveryNote,
    'suppliers' => l.tabSupplier,
    'supplier-invoices' => l.tabSupplierInvoice,
    'purchase-orders' => l.tabPurchaseOrder,
    'goods-receipts' => l.tabGoodsReceipt,
    _ => '',
  };
  return last == 'new' ? kind : '$kind $short'.trim();
}

/// Wide layouts: the tab strip above the workspace, with the main area as its first tab.
class WorkspaceTabStrip extends ConsumerWidget {
  const WorkspaceTabStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    final n = ref.read(workspaceProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            _TabChip(
              key: const ValueKey('tab-home'),
              label: context.l10n.workspaceOverview,
              icon: AppIcons.home,
              selected: ws.active == null,
              onTap: n.focusHome,
            ),
            for (final t in ws.tabs)
              _TabChip(
                key: ValueKey('tab-${t.id}'),
                label: tabLabel(context.l10n, t),
                selected: t.id == ws.active,
                dirty: n.dirtyOf(t.id),
                onTap: () => n.focus(t.id),
                onClose: () => requestCloseTab(context, ref, t.id),
              ),
          ],
        ),
      ),
    );
  }
}

/// One entry of the tab strip: label, unsaved marker and close button.
class _TabChip extends StatelessWidget {
  const _TabChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.dirty,
    this.onClose,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final ValueNotifier<bool>? dirty;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Listener(
      // Middle-click closes a tab, as in a browser.
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kMiddleMouseButton) {
          onClose?.call();
        }
      },
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: Material(
          color: selected ? scheme.surface : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220, minWidth: 80),
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: onClose == null ? 12 : 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      // The chip's own label covers the text; keep the other children
                      // (unsaved marker, close button) in the semantics tree.
                      child: ExcludeSemantics(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    ),
                    if (dirty != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: dirty!,
                        builder: (_, d, _) => d
                            ? Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: scheme.primary,
                                  semanticLabel:
                                      context.l10n.unsavedChangesTitle,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    if (onClose != null)
                      IconButton(
                        tooltip: context.l10n.closeTab,
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(AppIcons.close),
                        onPressed: onClose,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Narrow layouts: the open tabs in a menu of the app bar (the tab strip does not fit).
class WorkspaceMenuButton extends ConsumerWidget {
  const WorkspaceMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ws = ref.watch(workspaceProvider);
    if (ws.tabs.isEmpty) return const SizedBox.shrink();
    final n = ref.read(workspaceProvider.notifier);
    return PopupMenuButton<int>(
      key: const ValueKey('tab-menu'),
      tooltip: context.l10n.openTabs,
      icon: Badge.count(count: ws.tabs.length, child: const Icon(AppIcons.tab)),
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: -1,
          checked: ws.active == null,
          child: Text(context.l10n.workspaceOverview),
        ),
        for (final t in ws.tabs)
          CheckedPopupMenuItem(
            value: t.id,
            checked: t.id == ws.active,
            child: Text(tabLabel(context.l10n, t)),
          ),
        if (ws.active != null) const PopupMenuDivider(),
        if (ws.active != null)
          PopupMenuItem(value: -2, child: Text(context.l10n.closeTab)),
      ],
      onSelected: (v) {
        if (v == -1) n.focusHome();
        if (v == -2) requestCloseTab(context, ref, ws.active!);
        if (v >= 0) n.focus(v);
      },
    );
  }
}

/// Makes a list row open its record in a tab with a middle-click or ctrl-click (in the
/// background), and offers "open in new tab" on right-click or long press. A plain click is left
/// to the row.
class OpenInTab extends ConsumerWidget {
  const OpenInTab({super.key, required this.location, required this.child});

  final String? location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = location;
    if (loc == null || !isDetailLocation(loc)) return child;
    final n = ref.read(workspaceProvider.notifier);

    Future<void> menu(Offset at) async {
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final v = await showMenu<bool>(
        context: context,
        position: RelativeRect.fromRect(
          at & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: [
          PopupMenuItem(value: true, child: Text(context.l10n.openInNewTab)),
        ],
      );
      if (v == true) n.open(loc, focus: false);
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        if (e.kind == PointerDeviceKind.mouse &&
            e.buttons == kMiddleMouseButton) {
          n.open(loc, focus: false);
        } else if (e.buttons == kPrimaryButton &&
            (HardwareKeyboard.instance.isControlPressed ||
                HardwareKeyboard.instance.isMetaPressed)) {
          n.backgroundNextOpen();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (d) => menu(d.globalPosition),
        onLongPressStart: (d) => menu(d.globalPosition),
        child: child,
      ),
    );
  }
}
