import 'package:material_ui/material_ui.dart';

import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';

/// A group of navigation destinations shown together in the rail (Sales, Service, ...). The
/// application switcher lists the groups; the rail shows the destinations of the active one.
class AppGroup {
  const AppGroup(this.id, this.label, this.icon, this.art, this.paths);

  /// Stable id, also used in widget keys (`app-group-<id>`).
  final String id;
  final String Function(AppLocalizations l) label;

  /// Plain icon, used where the artwork is not wanted.
  final IconData icon;

  /// Artwork name in `assets/icons/<art>.svg`.
  final String art;

  /// Destination paths in the group, in menu order.
  final List<String> paths;

  /// Whether the destination at [path] belongs to the group.
  bool contains(String path) => paths.contains(path);
}

/// All groups. A destination that belongs to none is still reachable through the flat list
/// (the shell then shows every destination).
final appGroups = <AppGroup>[
  AppGroup(
    'sales',
    (l) => l.appGroupSales,
    AppIcons.requestQuote,
    'quotations',
    [
      '/opportunities',
      '/quotations',
      '/configurator',
      '/configurator/builder',
      '/orders',
      '/delivery',
    ],
  ),
  AppGroup(
    'service',
    (l) => l.appGroupService,
    AppIcons.supportAgent,
    'helpdesk',
    ['/helpdesk', '/kb', '/repairs', '/packages', '/intake', '/jobs'],
  ),
  AppGroup(
    'operations',
    (l) => l.appGroupOperations,
    AppIcons.precisionManufacturing,
    'production',
    ['/production', '/shipping', '/stock', '/planning'],
  ),
  AppGroup(
    'master',
    (l) => l.appGroupMasterData,
    AppIcons.business,
    'customers',
    ['/customers', '/products', '/price-lists'],
  ),
  AppGroup(
    'backoffice',
    (l) => l.appGroupBackOffice,
    AppIcons.accountBalance,
    'finance',
    ['/purchasing', '/finance'],
  ),
  AppGroup(
    'insight',
    (l) => l.appGroupInsight,
    AppIcons.tableChart,
    'reports',
    ['/reports', '/todo', '/admin'],
  ),
];

/// The group that holds the destination at [path], or null.
AppGroup? groupOfPath(String path) {
  for (final g in appGroups) {
    if (g.contains(path)) return g;
  }
  return null;
}

/// The groups with at least one destination in [visiblePaths] (the permitted ones).
List<AppGroup> visibleGroups(Iterable<String> visiblePaths) {
  final set = visiblePaths.toSet();
  return [
    for (final g in appGroups)
      if (g.paths.any(set.contains)) g,
  ];
}
