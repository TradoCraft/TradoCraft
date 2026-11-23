import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'api.dart';
import 'brand.dart';
import 'detail_routes.dart';
import 'environment_ui.dart';
import 'environments.dart';
import 'profile.dart';
import 'profile_badge.dart';
import 'session.dart';
import 'shortcuts/actions.dart';
import 'shortcuts/help_dialog.dart';
import 'shortcuts/key_hint.dart';
import 'shortcuts/preferences_dialog.dart';
import 'shortcuts/registry.dart';
import 'worker_ui.dart';
import 'workspace.dart';
import '../features/todo/todo_badge.dart';
import '../features/todo/todo_quick_add.dart';
import '../features/todo/todo_repository.dart';
import '../features/tutorial/targets.dart';
import '../core/navigation/app_groups.dart';
import '../core/navigation/app_switcher.dart';
import '../core/navigation/breadcrumbs.dart';
import '../core/navigation/global_search.dart';
import '../core/navigation/notifications.dart';
import '../core/theme/theme_mode.dart';
import '../l10n/l10n.dart';
import '../shared/app_icons.dart';
import '../shared/module_icon.dart';

class _Dest {
  const _Dest(
    this.path,
    this.label,
    this.icon,
    this.permission, {
    this.unless,
    this.alsoFor = const [],
    this.alsoPaths = const [],
  });
  final String path;
  final String Function(AppLocalizations l) label;
  final IconData icon;

  /// The permission that makes the section useful; people without it do not see the tab.
  final String permission;

  /// A permission that hides the tab again, because another tab already covers this section.
  final String? unless;

  /// Further permissions that also make the tab visible (e.g. price zone management, imports).
  final List<String> alsoFor;

  /// Detail locations that belong to this section (e.g. `/suppliers`), so a tab showing one
  /// highlights this destination.
  final List<String> alsoPaths;

  /// Whether [location] belongs to this destination.
  bool matches(String location) =>
      location.startsWith(path) || alsoPaths.any(location.startsWith);

  /// Whether a user with [perms] sees this destination.
  bool visibleFor(List<String> perms) =>
      (perms.contains(permission) || alsoFor.any(perms.contains)) &&
      (unless == null || !perms.contains(unless));
}

/// The artwork of each section in the navigation (`assets/icons/<name>.svg`).
const _sectionArt = {
  '/opportunities': 'opportunities',
  '/quotations': 'quotations',
  '/configurator': 'configurator',
  '/configurator/builder': 'configurator',
  '/orders': 'orders',
  '/delivery': 'delivery',
  '/production': 'production',
  '/shipping': 'shipping',
  '/helpdesk': 'helpdesk',
  '/kb': 'support_knowledge',
  '/repairs': 'service',
  '/packages': 'packages',
  '/intake': 'intake',
  '/jobs': 'work_order',
  '/stock': 'warehouse',
  '/planning': 'planning',
  '/customers': 'customers',
  '/products': 'product',
  '/purchasing': 'purchasing',
  '/finance': 'finance',
  '/reports': 'reports',
  '/admin': 'admin',
};

/// The icon of a navigation entry: the section artwork, or the plain icon when it has none.
Widget _destIcon(_Dest d) {
  final art = _sectionArt[d.path];
  // The label of the destination names it; the file name of the artwork must not add to it.
  final icon = art == null
      ? Icon(d.icon)
      : ExcludeSemantics(child: ModuleIcon(art));
  // The to-do entry carries the number of open to-dos on the plate of the user.
  return d.path == '/todo' ? TodoNavBadge(child: icon) : icon;
}

final _allDestinations = [
  _Dest(
    '/opportunities',
    (l) => l.opportunities,
    AppIcons.trendingUp,
    'opportunities.read',
  ),
  _Dest(
    '/quotations',
    (l) => l.quotations,
    AppIcons.requestQuote,
    'quotations.read',
  ),
  _Dest(
    '/configurator',
    (l) => l.configurator,
    AppIcons.dashboardCustomize,
    'configurator.use',
  ),
  // Designers who do not run configurators (e.g. product managers) go straight to the builder.
  _Dest(
    '/configurator/builder',
    (l) => l.configurator,
    AppIcons.dashboardCustomize,
    'configurator.design',
    unless: 'configurator.use',
  ),
  _Dest('/orders', (l) => l.orders, AppIcons.inventory, 'orders.read'),
  _Dest('/delivery', (l) => l.deliveries, AppIcons.outbox, 'delivery.read'),
  _Dest(
    '/production',
    (l) => l.production,
    AppIcons.precisionManufacturing,
    'production.read',
  ),
  _Dest(
    '/shipping',
    (l) => l.shippingRequests,
    AppIcons.localShipping,
    'shipping.manage',
  ),
  _Dest('/helpdesk', (l) => l.helpdesk, AppIcons.supportAgent, 'helpdesk.read'),
  _Dest('/kb', (l) => l.kbTitle, AppIcons.menuBook, 'kb.read'),
  _Dest('/repairs', (l) => l.repairs, AppIcons.buildCircle, 'repairs.read'),
  _Dest(
    '/packages',
    (l) => l.packagesReceiving,
    AppIcons.moveToInbox,
    'packages.read',
  ),
  _Dest(
    '/intake',
    (l) => l.packagesIntake,
    AppIcons.factCheck,
    'repairs.intake',
  ),
  _Dest('/jobs', (l) => l.jobs, AppIcons.engineering, 'field.read'),
  _Dest('/stock', (l) => l.stockTitle, AppIcons.warehouse, 'inventory.read'),
  _Dest(
    '/planning',
    (l) => l.planningTitle,
    AppIcons.calendarViewWeek,
    'planning.read',
  ),
  _Dest('/customers', (l) => l.customers, AppIcons.business, 'customers.read'),
  _Dest('/products', (l) => l.products, AppIcons.inventory2, 'products.read'),
  _Dest('/price-lists', (l) => l.plTitle, AppIcons.article, 'price_lists.read'),
  _Dest(
    '/purchasing',
    (l) => l.purchasing,
    AppIcons.shoppingCart,
    'purchasing.read',
    alsoPaths: ['/suppliers', '/purchase-orders', '/goods-receipts'],
  ),
  _Dest(
    '/finance',
    (l) => l.finance,
    AppIcons.accountBalance,
    'finance.read',
    alsoFor: ['billing.read', 'rebates.admin'],
    alsoPaths: ['/supplier-invoices'],
  ),
  _Dest('/reports', (l) => l.crTitle, AppIcons.tableChart, 'reports.read'),
  _Dest('/todo', (l) => l.todoTitle, AppIcons.checklist, 'todo.use'),
  _Dest(
    '/admin',
    (l) => l.adminTitle,
    AppIcons.adminPanelSettings,
    'users.admin',
    alsoFor: ['prices.write', 'products.write', 'imports.admin'],
  ),
];

/// Returns the category and module labels used by the app switcher and rail.
List<String> moduleMenuPath(AppLocalizations l, String location) {
  final path = Uri.parse(location).path;
  final destination = _allDestinations.where((d) => d.matches(path)).firstOrNull;
  if (destination == null) return const [];
  final group = groupOfPath(destination.path);
  return [
    if (group != null) ...[l.appSwitcherTooltip, group.label(l)],
    destination.label(l),
  ];
}

/// Navigation frame: a side rail on desktop/tablet, a bottom bar on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final me = ref.watch(meProvider);
    ref.watch(userPreferencesProvider);
    // Keeps the to-do badge fresh (only while signed in and holding todo.use).
    ref.watch(todoBadgeSyncProvider);
    // Show the sections the user has rights for (all, while the user is still loading), so a
    // technician sees "My jobs" and not a row of tabs that answer "forbidden".
    final perms = me.value?.permissions;
    final destinations = [
      for (final d in _allDestinations)
        if (perms == null || d.visibleFor(perms)) d,
    ];
    final workspace = ref.watch(workspaceProvider);
    final workspaceNotifier = ref.read(workspaceProvider.notifier);
    // Where the main area is (a detail location is only handed to a tab, see DetailPortal).
    if (!isDetailLocation(location)) workspaceNotifier.homeLocation = location;
    // The section of the focused tab is highlighted, so a ticket tab belongs to Helpdesk.
    final shown = workspace.activeTab?.location ?? location;
    final found = destinations.indexWhere((d) => d.matches(shown));
    if (found < 0 && destinations.isNotEmpty && perms != null) {
      // The current page is not for this user (e.g. the default start page): go to their first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(destinations.first.path);
      });
    }
    if (destinations.isEmpty) {
      // Still shows the environment (and its switcher): a user without access here may have it
      // in another environment.
      return Scaffold(
        body: Column(
          children: [
            const EnvironmentBanner(),
            Expanded(child: Center(child: Text(context.l10n.noAccess))),
          ],
        ),
      );
    }
    final index = found < 0 ? 0 : found;
    void go(int i) {
      workspaceNotifier.focusHome();
      context.go(destinations[i].path);
    }

    // The rail and the bar show the destinations of the active group (all of them when the
    // current section is in no group). Menu 1-9 and Home keep using the flat list above.
    final activeGroup = found < 0 ? null : groupOfPath(destinations[found].path);
    final groups = visibleGroups([for (final d in destinations) d.path]);
    final inGroup = [
      for (var i = 0; i < destinations.length; i++)
        if (activeGroup == null || activeGroup.contains(destinations[i].path)) i,
    ];
    // A rail or bar needs two entries: a group with one permitted entry shows the flat list.
    final shownIdx = inGroup.length >= 2
        ? inGroup
        : [for (var i = 0; i < destinations.length; i++) i];
    final shownSel = shownIdx.contains(index) ? shownIdx.indexOf(index) : 0;
    void goShown(int k) => go(shownIdx[k]);
    final switcher = groups.length < 2
        ? null
        : AppSwitcherButton(
            groups: groups,
            active: activeGroup,
            onSelected: (g) {
              final i = destinations.indexWhere((d) => g.contains(d.path));
              if (i >= 0) go(i);
            },
          );

    // Menu 1-9 pick the n-th entry of the permission-filtered list; Home is the first one (the
    // main area of the first permitted section). Back lives in each tab (see workspace.dart).
    // New to-do needs `todo.use` (the server also takes it away when the module is off).
    final canTodo = perms?.contains('todo.use') ?? false;
    // Global search: "Go to" lists the sections of this user; opening one is like a menu click.
    final searchDestinations = [
      for (final d in destinations) (path: d.path, label: d.label(context.l10n)),
    ];
    void searchGoTo(String path) {
      workspaceNotifier.focusHome();
      context.go(path);
    }

    void openSearch() => showGlobalSearch(
      context,
      destinations: searchDestinations,
      onGoTo: searchGoTo,
    );
    final shellActions = <ShortcutAction, VoidCallback?>{
      ShortcutAction.home: () => go(0),
      ShortcutAction.help: () => showShortcutHelp(context),
      ShortcutAction.palette: openSearch,
      if (canTodo) ShortcutAction.newTodo: () => showTodoQuickAdd(context, ref),
      for (
        var i = 0;
        i < destinations.length && i < ShortcutAction.menus.length;
        i++
      )
        ShortcutAction.menus[i]: () => go(i),
    };
    // The badge of entry [i] (only the first nine have a shortcut).
    Widget hinted(int i, Widget icon) => i < ShortcutAction.menus.length
        ? KeyHint(action: ShortcutAction.menus[i], child: icon)
        : icon;

    final profile = ref.watch(profileProvider);
    final activeEnv = ref.watch(activeEnvironmentProvider);
    final badge = profile == null
        ? null
        : ProfileBadge(profile: profile, roles: me.value?.roles ?? const []);

    final userMenuButton = PopupMenuButton<String>(
      tooltip: context.l10n.account,
      icon: const Icon(AppIcons.accountCircle),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            me.when(
              data: (m) =>
                  '${m.displayName}\n${m.company.name}\n${m.roles.join(', ')}'
                  '${profile == null ? '' : '\n${context.l10n.profileTooltip(profile)}'}',
              loading: () => '…',
              error: (e, _) => errorMessage(e),
            ),
          ),
        ),
        const PopupMenuDivider(),
        // Always reachable, whatever the keyboard offers.
        if (canTodo)
          PopupMenuItem(
            key: const ValueKey('account-new-todo'),
            value: 'todo',
            child: Row(
              children: [
                Expanded(child: Text(context.l10n.shortcutNewTodo)),
                const SizedBox(width: 16),
                Text(
                  ShortcutAction.newTodo.describe(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        PopupMenuItem(value: 'tutorial', child: Text(context.l10n.tutTitle)),
        PopupMenuItem(
          key: const ValueKey('account-preferences'),
          value: 'preferences',
          child: Text(context.l10n.userPreferences),
        ),
        PopupMenuItem(
          value: 'env',
          child: Text(context.l10n.envSwitchMenu(activeEnv.name)),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, child: Text(context.l10n.appLanguage)),
        CheckedPopupMenuItem(
          value: 'lang:',
          checked: ref.watch(localeProvider) == null,
          child: Text(context.l10n.deviceLanguage),
        ),
        for (final code in languageCodes)
          CheckedPopupMenuItem(
            value: 'lang:$code',
            checked: ref.watch(localeProvider)?.languageCode == code,
            child: Text(languageName(code)),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(enabled: false, child: Text(context.l10n.themeMenu)),
        for (final (mode, label) in [
          (ThemeMode.system, context.l10n.themeSystem),
          (ThemeMode.light, context.l10n.themeLight),
          (ThemeMode.dark, context.l10n.themeDark),
        ])
          CheckedPopupMenuItem(
            value: 'theme:${mode.name}',
            checked: ref.watch(themeModeProvider) == mode,
            child: Text(label),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'signout', child: Text(context.l10n.signOut)),
      ],
      onSelected: (v) {
        if (v == 'signout') ref.read(sessionProvider.notifier).signOut();
        if (v == 'env') showEnvironmentSwitcher(context);
        if (v == 'tutorial') context.push('/tutorial');
        if (v == 'preferences') showUserPreferences(context);
        if (v == 'todo') showTodoQuickAdd(context, ref);
        if (v.startsWith('theme:')) {
          ref
              .read(themeModeProvider.notifier)
              .set(ThemeMode.values.byName(v.substring(6)));
        }
        if (v.startsWith('lang:')) {
          final code = v.substring(5);
          ref
              .read(localeProvider.notifier)
              .set(code.isEmpty ? null : Locale(code));
        }
      },
    );

    final userMenu = TutorialTarget(id: 'user-menu', child: userMenuButton);
    final searchButton = GlobalSearchButton(
      destinations: searchDestinations,
      onGoTo: searchGoTo,
    );

    if (wide) {
      return Scaffold(
        body: ShortcutScope(
          layer: ShortcutLayer.shell,
          actions: shellActions,
          child: Column(
            children: [
              const EnvironmentBanner(),
              const WorkerBanner(),
              Expanded(
                child: Row(
                  children: [
                    // Many destinations do not fit a short window: scroll, but keep the user menu at the
                    // bottom when there is room to spare.
                    LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: NavigationRail(
                              selectedIndex: shownSel,
                              onDestinationSelected: goShown,
                              labelType: NavigationRailLabelType.all,
                              leading: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      brandName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (badge != null) ...[
                                      const SizedBox(height: 6),
                                      badge,
                                    ],
                                    searchButton,
                                    if (switcher != null) ...[
                                      const SizedBox(height: 6),
                                      switcher,
                                    ],
                                  ],
                                ),
                              ),
                              trailing: Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const NotificationsButton(),
                                      userMenu,
                                    ],
                                  ),
                                ),
                              ),
                              destinations: [
                                for (final i in shownIdx)
                                  NavigationRailDestination(
                                    icon: hinted(i, _destIcon(destinations[i])),
                                    label: Text(
                                      destinations[i].label(context.l10n),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: Column(
                        children: [
                          SectionBreadcrumbs(
                            section: destinations[index].label(context.l10n),
                            onSection: () => go(index),
                          ),
                          Expanded(
                            child: WorkspaceBody(home: child, wide: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(me.value?.company.name ?? brandName),
        actions: [
          ?switcher,
          ?badge,
          searchButton,
          const WorkspaceMenuButton(),
          const NotificationsButton(),
          userMenu,
        ],
      ),
      body: ShortcutScope(
        layer: ShortcutLayer.shell,
        actions: shellActions,
        child: Column(
          children: [
            const EnvironmentBanner(),
            const WorkerBanner(),
            Expanded(child: WorkspaceBody(home: child, wide: false)),
          ],
        ),
      ),
      bottomNavigationBar: _NarrowNavigationBar(
        destinations: [for (final i in shownIdx) destinations[i]],
        selectedIndex: shownSel,
        onSelected: goShown,
        iconOf: _destIcon,
      ),
    );
  }
}

/// Bottom navigation bar for narrow viewports. Caps visible destinations at 5 by folding any
/// overflow beyond the first 4 into a `More` bottom sheet.
class _NarrowNavigationBar extends StatelessWidget {
  const _NarrowNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.iconOf,
  });

  final List<_Dest> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget Function(_Dest) iconOf;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (destinations.length <= 5) {
      return NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelected,
        destinations: [
          for (final d in destinations)
            NavigationDestination(icon: iconOf(d), label: d.label(l)),
        ],
      );
    }
    const visibleCount = 4;
    final moreLabel = MaterialLocalizations.of(context).moreButtonTooltip;
    return NavigationBar(
      selectedIndex: selectedIndex >= visibleCount
          ? visibleCount
          : selectedIndex,
      onDestinationSelected: (i) async {
        if (i < visibleCount) {
          onSelected(i);
          return;
        }
        final picked = await showModalBottomSheet<int>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var j = visibleCount; j < destinations.length; j++)
                  ListTile(
                    leading: iconOf(destinations[j]),
                    title: Text(destinations[j].label(l)),
                    selected: selectedIndex == j,
                    onTap: () => Navigator.of(ctx).pop(j),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onSelected(picked);
      },
      destinations: [
        for (final d in destinations.take(visibleCount))
          NavigationDestination(icon: iconOf(d), label: d.label(l)),
        NavigationDestination(
          key: const ValueKey('nav-more-button'),
          icon: const Icon(AppIcons.moreVert),
          label: moreLabel,
        ),
      ],
    );
  }
}
