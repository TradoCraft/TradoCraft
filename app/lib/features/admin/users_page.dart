import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/entity_list.dart';
import 'link_identity_dialog.dart';
import 'user_dialog.dart';
import '../../shared/app_icons.dart';

/// Members of the active company with their roles, module switches and status.
class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  final _list = GlobalKey<EntityListState<AdminUser>>();

  /// null = all, true = active only, false = deactivated only.
  bool? _active;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final api = ref.watch(apiProvider);
    Widget grey(AdminUser u, Widget w) =>
        u.active ? w : Opacity(opacity: 0.5, child: w);
    return EntityList<AdminUser>(
      key: _list,
      title: l.adminUsers,
      createLabel: l.newUser,
      load: (q, offset, limit) async {
        // The endpoint returns every member; search and the active filter run here.
        final all = await api.core.listAdminUsers();
        final needle = q?.toLowerCase();
        final items = [
          for (final u in all)
            if ((_active == null || u.active == _active) &&
                (needle == null ||
                    u.displayName.toLowerCase().contains(needle) ||
                    u.email.toLowerCase().contains(needle)))
              u,
        ];
        return (items, items.length);
      },
      filters: DropdownButton<bool?>(
        value: _active,
        items: [
          DropdownMenuItem(value: null, child: Text(l.userFilterAll)),
          DropdownMenuItem(value: true, child: Text(l.userFilterActive)),
          DropdownMenuItem(value: false, child: Text(l.userFilterInactive)),
        ],
        onChanged: (v) {
          setState(() => _active = v);
          _list.currentState?.reload();
        },
      ),
      columns: [
        EntityColumn(
          l.name,
          (u) => u.displayName,
          flex: 2,
          cell: (_, u) =>
              grey(u, Text(u.displayName, overflow: TextOverflow.ellipsis)),
        ),
        EntityColumn(
          l.email,
          (u) => u.email,
          flex: 3,
          cell: (_, u) =>
              grey(u, Text(u.email, overflow: TextOverflow.ellipsis)),
        ),
        EntityColumn(
          l.roles,
          (u) => u.roles.map(l.roleName).join(', '),
          flex: 3,
          cell: (_, u) => grey(
            u,
            Text(
              u.roles.map(l.roleName).join(', '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        EntityColumn(
          l.userDisabledModules,
          (u) => u.disabledModules.map(l.moduleName).join(', '),
          flex: 3,
          cell: (_, u) => grey(
            u,
            Text(
              u.disabledModules.map(l.moduleName).join(', '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        EntityColumn(
          l.status,
          (u) => [
            u.active ? l.active : l.inactive,
            if (!u.hasSignedIn) l.userNotSignedIn,
          ].join(' · '),
          flex: 3,
          cell: (_, u) => Wrap(
            spacing: 4,
            children: [
              Chip(
                label: Text(u.active ? l.active : l.inactive),
                visualDensity: VisualDensity.compact,
              ),
              if (!u.hasSignedIn)
                Chip(
                  label: Text(l.userNotSignedIn),
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(AppIcons.mail, size: 16),
                ),
            ],
          ),
        ),
        if (can(ref, 'identity.admin'))
          EntityColumn(
            '',
            (u) => '',
            flex: 2,
            cell: (_, u) => TextButton.icon(
              key: ValueKey('link-identity-${u.userId}'),
              onPressed: () => showLinkIdentityDialog(context, u),
              icon: const Icon(Icons.link, size: 18),
              label: Text(l.idpLinkIdentity),
            ),
          ),
      ],
      onCreate: () => showUserDialog(context),
      onOpen: (u) => showUserDialog(context, user: u),
    );
  }
}
