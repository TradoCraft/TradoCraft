import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import 'modules_page.dart';
import '../../shared/app_icons.dart';

final adminRolesProvider = FutureProvider.autoDispose<List<RoleInfo>>(
  (ref) => ref.watch(apiProvider).core.listRoles(),
);

/// Opens the create dialog ([user] null) or the edit dialog. Resolves to true when data changed.
Future<bool?> showUserDialog(BuildContext context, {AdminUser? user}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => UserDialog(user: user),
    );

class UserDialog extends ConsumerStatefulWidget {
  const UserDialog({super.key, this.user});
  final AdminUser? user;

  @override
  ConsumerState<UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<UserDialog> {
  late final _email = TextEditingController(text: widget.user?.email);
  late final _name = TextEditingController(text: widget.user?.displayName);
  late final Set<String> _roles = {...?widget.user?.roles};
  late final Set<String> _disabled = {...?widget.user?.disabledModules};
  late bool _active = widget.user?.active ?? true;
  bool _busy = false;
  bool _changed = false;

  AdminUser? get _user => widget.user;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _roles.isNotEmpty &&
      (_user != null || _email.text.contains('@'));

  Future<void> _save(List<RoleInfo> catalogue) async {
    setState(() => _busy = true);
    final core = ref.read(apiProvider).core;
    // Keep the catalogue's order so the stored arrays are stable.
    final roles = [
      for (final r in catalogue)
        if (_roles.contains(r.role)) r.role,
    ];
    final disabled = _disabled.toList()..sort();
    final ok = await runAction(context, () async {
      final u = _user;
      if (u == null) {
        await core.createAdminUser(
          body: AdminUserCreate(
            email: _email.text.trim(),
            displayName: _name.text.trim(),
            roles: roles,
            disabledModules: disabled,
          ),
        );
      } else {
        await core.updateAdminUser(
          id: u.userId,
          body: AdminUserUpdate(
            active: _active,
            disabledModules: disabled,
            displayName: _name.text.trim(),
            roles: roles,
          ),
        );
      }
    }, success: _user == null ? context.l10n.userCreated : context.l10n.saved);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  Future<void> _invite() async {
    final ok = await runAction(
      context,
      () => ref.read(apiProvider).core.inviteAdminUser(id: _user!.userId),
      success: context.l10n.userInvitationSent,
    );
    if (ok) _changed = true;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final roles = ref.watch(adminRolesProvider);
    final modules = ref.watch(adminModulesProvider);
    final meId = ref.watch(meProvider).value?.userId;
    final self = _user != null && _user!.userId == meId;
    final catalogue = roles.value;
    return AlertDialog(
      title: Text(_user == null ? l.newUser : l.editUser),
      content: SizedBox(
        width: 520,
        child: roles.hasError || modules.hasError
            ? Text(errorMessage((roles.error ?? modules.error)!))
            : catalogue == null || modules.value == null
            ? const LinearProgressIndicator()
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_user == null) ...[
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(labelText: l.email),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      Text(_user!.email),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _name,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: l.name),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.roles,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final r in catalogue)
                          Tooltip(
                            message: l.userRolePermissions(
                              r.permissions.length,
                            ),
                            child: FilterChip(
                              key: ValueKey('role-${r.role}'),
                              label: Text(l.roleName(r.role)),
                              selected: _roles.contains(r.role),
                              // The server refuses dropping your own admin role (409).
                              onSelected:
                                  self &&
                                      r.role == 'admin' &&
                                      _roles.contains('admin')
                                  ? null
                                  : (on) => setState(() {
                                      if (on) {
                                        _roles.add(r.role);
                                      } else {
                                        _roles.remove(r.role);
                                      }
                                    }),
                            ),
                          ),
                      ],
                    ),
                    if (self)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          l.userCannotDropOwnAdmin,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      l.adminModules,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      l.userModulesHelp,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final m in modules.value!)
                      SwitchListTile(
                        key: ValueKey('module-${m.code}'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.moduleName(m.code)),
                        subtitle: Text(
                          [
                            if (!m.enabled) l.userModuleCompanyOff,
                            if (m.requires.isNotEmpty)
                              l.moduleRequires(
                                m.requires.map(l.moduleName).join(', '),
                              ),
                          ].join(' · '),
                        ),
                        // A module the company switched off cannot be given back to one person.
                        value: m.enabled && !_disabled.contains(m.code),
                        onChanged: !m.enabled
                            ? null
                            : (on) => setState(() {
                                if (on) {
                                  _disabled.remove(m.code);
                                } else {
                                  _disabled.add(m.code);
                                }
                              }),
                      ),
                    if (_user != null) ...[
                      const Divider(),
                      SwitchListTile(
                        key: const ValueKey('active'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.active),
                        subtitle: Text(
                          self ? l.userCannotDeactivateSelf : l.userActiveHelp,
                        ),
                        value: _active,
                        onChanged: self
                            ? null
                            : (v) => setState(() => _active = v),
                      ),
                      if (!_user!.hasSignedIn && _user!.active)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _invite,
                            icon: const Icon(AppIcons.mail),
                            label: Text(l.userResendInvitation),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _changed),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _busy || catalogue == null || !_valid
              ? null
              : () => _save(catalogue),
          child: Text(l.save),
        ),
      ],
    );
  }
}
