import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';

/// Opens the dialog that links [user] to a subject at an identity provider (or clears the link).
/// Resolves to true when the link was changed.
Future<bool?> showLinkIdentityDialog(BuildContext context, AdminUser user) =>
    showDialog<bool>(
      context: context,
      builder: (_) => LinkIdentityDialog(user: user),
    );

/// Sets or clears the identity a user signs in with, for providers that use the rule
/// 'only existing subjects'. An empty subject clears the binding.
class LinkIdentityDialog extends ConsumerStatefulWidget {
  const LinkIdentityDialog({super.key, required this.user});

  /// The user to link.
  final AdminUser user;

  @override
  ConsumerState<LinkIdentityDialog> createState() => _LinkIdentityDialogState();
}

class _LinkIdentityDialogState extends ConsumerState<LinkIdentityDialog> {
  final _subject = TextEditingController();
  late final Future<List<IdentityProviderInfo>> _providers = ref
      .read(apiProvider)
      .admin
      .listProviders()
      .then(
        (all) => [
          for (final p in all)
            if (!p.readOnly) p,
        ],
      );
  String? _issuer;
  bool _busy = false;

  @override
  void dispose() {
    _subject.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final subject = _subject.text.trim();
    setState(() => _busy = true);
    final body = subject.isEmpty
        ? const OidcSubjectInput()
        : OidcSubjectInput(issuer: _issuer, subject: subject);
    final ok = await runAction(
      context,
      () => ref
          .read(apiProvider)
          .admin
          .setOidcSubject(id: widget.user.userId, body: body),
      success: subject.isEmpty ? l.idpLinkCleared : l.idpLinkSaved,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.idpLinkTitle(widget.user.displayName)),
      content: SizedBox(
        width: 440,
        child: FutureBuilder<List<IdentityProviderInfo>>(
          future: _providers,
          builder: (context, snap) {
            if (snap.hasError) return Text(errorMessage(snap.error!));
            final list = snap.data;
            if (list == null) return const LinearProgressIndicator();
            _issuer ??= list.isEmpty ? null : list.first.issuer;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.idpLinkExplain),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  Text(l.idpLinkNoProviders)
                else ...[
                  DropdownButtonFormField<String>(
                    key: const ValueKey('link-provider'),
                    initialValue: _issuer,
                    decoration: InputDecoration(labelText: l.idpLinkProvider),
                    items: [
                      for (final p in list)
                        DropdownMenuItem(value: p.issuer, child: Text(p.name)),
                    ],
                    onChanged: (v) => setState(() => _issuer = v),
                  ),
                  TextField(
                    key: const ValueKey('link-subject'),
                    controller: _subject,
                    decoration: InputDecoration(labelText: l.idpLinkSubject),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('link-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
