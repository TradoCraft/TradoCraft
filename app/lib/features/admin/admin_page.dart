import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../shared/app_icons.dart';

import '../../l10n/l10n.dart';
import 'identity_providers_page.dart';
import 'modules_page.dart';
import 'price_zones_page.dart';
import 'users_page.dart';

/// Administration: one destination with a switch between users, modules, price zones and
/// identity providers (each shown with its own permission).
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
      if (can(ref, 'identity.admin')) 'identity',
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
                            'identity' => l.adminIdentityProviders,
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
            'identity' => const IdentityProvidersPage(),
            'users' => const UsersPage(),
            _ => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}
