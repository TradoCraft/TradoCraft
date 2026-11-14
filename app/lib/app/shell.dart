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
import 'shortcuts/key_hint.dart';
import 'shortcuts/registry.dart';
import 'worker_ui.dart';
import 'workspace.dart';
import '../features/todo/todo_badge.dart';
import '../features/todo/todo_quick_add.dart';
import '../features/todo/todo_repository.dart';
import '../features/tutorial/targets.dart';
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

/// Navigation frame: a side rail on desktop/tablet, a bottom bar on phones.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final me = ref.watch(meProvider);
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

    // Menu 1-9 pick the n-th entry of the permission-filtered list; Home is the first one (the
    // main area of the first permitted section). Back lives in each tab (see workspace.dart).
    // New to-do needs `todo.use` (the server also takes it away when the module is off).
    final canTodo = perms?.contains('todo.use') ?? false;
    final shellActions = <ShortcutAction, VoidCallback?>{
      ShortcutAction.home: () => go(0),
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
        PopupMenuItem(value: 'signout', child: Text(context.l10n.signOut)),
      ],
      onSelected: (v) {
        if (v == 'signout') ref.read(sessionProvider.notifier).signOut();
        if (v == 'env') showEnvironmentSwitcher(context);
        if (v == 'tutorial') context.push('/tutorial');
        if (v == 'todo') showTodoQuickAdd(context, ref);
        if (v.startsWith('lang:')) {
          final code = v.substring(5);
          ref
              .read(localeProvider.notifier)
              .set(code.isEmpty ? null : Locale(code));
        }
      },
    );

    final userMenu = TutorialTarget(id: 'user-menu', child: userMenuButton);

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
                              selectedIndex: index,
                              onDestinationSelected: go,
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
                                  ],
                                ),
                              ),
                              trailing: Expanded(
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: userMenu,
                                ),
                              ),
                              destinations: [
                                for (var i = 0; i < destinations.length; i++)
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
                    Expanded(child: WorkspaceBody(home: child, wide: true)),
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
        actions: [?badge, const WorkspaceMenuButton(), userMenu],
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: go,
        destinations: [
          for (var i = 0; i < destinations.length; i++)
            NavigationDestination(
              icon: hinted(i, _destIcon(destinations[i])),
              label: destinations[i].label(context.l10n),
            ),
        ],
      ),
    );
  }
}
