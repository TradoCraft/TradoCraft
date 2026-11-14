import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/app_icons.dart';

import '../../l10n/l10n.dart';
import 'attribute_definitions_page.dart';
import 'audit_trail_page.dart';
import 'baseline_types_page.dart';
import 'identity_providers_page.dart';
import 'imports/imports_page.dart';
import 'modules_page.dart';
import 'price_zones_page.dart';
import 'users_page.dart';

/// Administration: one destination with a switch between users, modules, price zones,
/// attribute definitions, baseline types, identity providers, the audit trail and data import (each shown with its own permission).
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage> {
  String? _tab;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // User administration needs users.admin; price zones are open to prices.write.
    final isAdmin = can(ref, 'users.admin');
    final tabs = [
      if (isAdmin) 'users',
      if (isAdmin) 'modules',
      if (can(ref, 'prices.write')) 'zones',
      if (can(ref, 'products.write')) 'attributes',
      if (can(ref, 'products.write')) 'baseline',
      if (can(ref, 'identity.admin')) 'identity',
      if (can(ref, 'audit.view')) 'audit',
      if (can(ref, 'imports.admin')) 'import',
    ];
    final tab = tabs.contains(_tab) ? _tab! : (tabs.isEmpty ? '' : tabs.first);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (tabs.length > 1)
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      for (final t in tabs)
                        ButtonSegment(
                          value: t,
                          label: Text(switch (t) {
                            'users' => l.adminUsers,
                            'modules' => l.adminModules,
                            'attributes' => l.adminAttributes,
                            'baseline' => l.adminBaselineTypes,
                            'identity' => l.adminIdentityProviders,
                            'audit' => l.adminAuditTrail,
                            'import' => l.adminImport,
                            _ => l.adminPriceZones,
                          }),
                        ),
                    ],
                    selected: {tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                // The configurator builder lives with the configurators; designers start here too.
                if (can(ref, 'configurator.design'))
                  OutlinedButton.icon(
                    key: const ValueKey('admin-configurators'),
                    onPressed: () => context.push('/configurator/builder'),
                    icon: const Icon(AppIcons.dashboardCustomize),
                    label: Text(l.cfgbDesignTitle),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: switch (tab) {
            'modules' => const ModulesPage(),
            'zones' => const PriceZonesPage(),
            'attributes' => const AttributeDefinitionsPage(),
            'baseline' => const BaselineTypesPage(),
            'identity' => const IdentityProvidersPage(),
            'audit' => const AuditTrailPage(),
            'import' => const ImportsPage(),
            'users' => const UsersPage(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}
