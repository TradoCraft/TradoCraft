import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'identity_provider_dialog.dart';

/// The identity providers of the installation: the saved ones and, read-only, the one the server
/// reads from its environment. Fails with 403 for anybody but an administrator of the primary company.
final identityProvidersProvider =
    FutureProvider.autoDispose<List<IdentityProviderInfo>>(
      (ref) => ref.watch(apiProvider).admin.listProviders(),
    );

/// Whether [e] is the server's 403 for a caller who is not an administrator of the primary company.
bool isForbidden(Object e) => e is DioException && e.response?.statusCode == 403;

/// The 409 codes that mean a change could lock somebody out and can be repeated with confirmation.
const _lockoutCodes = {'last_identity_provider', 'own_identity_provider'};

/// Runs [call] without lock-out confirmation. When the server answers 409 with a lock-out code the
/// consequence is explained in a dialog and, when the user confirms, [call] runs again with
/// `confirm` true. Other errors go to [onError] or, without it, are shown as a snack bar. Returns
/// true when the change was made.
Future<bool> runWithLockoutGuard(
  BuildContext context,
  Future<void> Function(bool confirm) call, {
  String? success,
  void Function(Object error)? onError,
}) async {
  final l = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  void fail(Object e) {
    if (onError != null) {
      onError(e);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(errorMessage(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<bool> attempt(bool confirm) async {
    try {
      await call(confirm);
      if (success != null) {
        messenger.showSnackBar(SnackBar(content: Text(success)));
      }
      return true;
    } catch (e) {
      final code = errorCode(e);
      if (confirm || code == null || !_lockoutCodes.contains(code)) {
        fail(e);
        return false;
      }
      if (!context.mounted) return false;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: Text(l.idpLockoutTitle),
          content: Text(
            code == 'last_identity_provider'
                ? l.idpLockoutLast
                : l.idpLockoutOwn,
          ),
          actions: [
            TextButton(
              key: const ValueKey('idp-lockout-cancel'),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              key: const ValueKey('idp-lockout-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.idpLockoutContinue),
            ),
          ],
        ),
      );
      if (go != true) return false;
      return attempt(true);
    }
  }

  return attempt(false);
}

/// Administration of the identity providers (ADR 0052): list, add, edit, delete.
class IdentityProvidersPage extends ConsumerWidget {
  const IdentityProvidersPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, [
    IdentityProviderInfo? p,
  ]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => IdentityProviderDialog(provider: p),
    );
    if (saved == true) ref.invalidate(identityProvidersProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    IdentityProviderInfo p,
  ) async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.delete),
        content: Text(l.idpDeleteConfirm(p.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('idp-delete-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final admin = ref.read(apiProvider).admin;
    final ok = await runWithLockoutGuard(
      context,
      (confirm) => admin.deleteProvider(
        id: p.id!,
        confirmLockout: confirm ? true : null,
      ),
      success: l.idpDeleted,
    );
    if (ok) ref.invalidate(identityProvidersProvider);
  }

  /// The e-mail rule of [p] in words.
  String _rule(AppLocalizations l, IdentityProviderInfo p) {
    final base = switch (p.emailPolicy) {
      'trust_provider_email' => l.idpRuleTrust,
      'subject_only' => l.idpRuleSubject,
      _ => l.idpRuleVerified(p.verifiedClaim),
    };
    if (p.emailPolicy == 'subject_only' || p.allowedEmailDomains.isEmpty) {
      return base;
    }
    return '$base, ${l.idpRuleDomains(p.allowedEmailDomains.join(', '))}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final list = ref.watch(identityProvidersProvider);
    final me = ref.watch(meProvider).value;
    final theme = Theme.of(context);
    final forbidden = list.hasError && isForbidden(list.error!);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l.adminIdentityProviders,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            FilledButton.icon(
              key: const ValueKey('idp-add'),
              onPressed: list.hasValue ? () => _edit(context, ref) : null,
              icon: const Icon(Icons.add),
              label: Text(l.idpAdd),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(l.idpIntro),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.apartment_outlined),
            // The name is only known when the caller works in the primary company.
            title: Text(
              me != null && me.company.isPrimary
                  ? l.idpPrimaryCompany(me.company.name)
                  : l.idpPrimaryNote,
            ),
            subtitle: me != null && me.company.isPrimary
                ? Text(l.idpPrimaryNote)
                : null,
          ),
        ),
        const SizedBox(height: 8),
        if (forbidden)
          Card(
            key: const ValueKey('idp-readonly'),
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l.idpReadOnlyNotice),
            ),
          )
        else
          list.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Row(
              children: [
                Expanded(child: Text(errorMessage(e))),
                TextButton(
                  key: const ValueKey('idp-retry'),
                  onPressed: () => ref.invalidate(identityProvidersProvider),
                  child: Text(l.retry),
                ),
              ],
            ),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(l.idpNone),
                  )
                : Column(
                    children: [
                      for (final p in items)
                        Card(
                          key: ValueKey('idp-${p.id ?? 'env'}'),
                          child: ListTile(
                            title: Text(p.name),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.issuer),
                                Text(_rule(l, p)),
                                if (p.readOnly) Text(l.idpEnvExplain),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  children: [
                                    Chip(
                                      label: Text(
                                        p.enabled
                                            ? l.idpEnabled
                                            : l.idpDisabled,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    Chip(
                                      label: Text(
                                        p.source == 'env'
                                            ? l.idpSourceEnv
                                            : l.idpSourceDatabase,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            isThreeLine: true,
                            trailing: p.readOnly
                                ? null
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: ValueKey('idp-edit-${p.id}'),
                                        tooltip: l.edit,
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _edit(context, ref, p),
                                      ),
                                      IconButton(
                                        key: ValueKey('idp-del-${p.id}'),
                                        tooltip: l.delete,
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () =>
                                            _delete(context, ref, p),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}
