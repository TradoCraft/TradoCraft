import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import 'ticket_screen.dart' show teamsProvider;

/// The helpdesk mailboxes of the company (ADR 0054).
final mailboxesProvider = FutureProvider.autoDispose<List<Mailbox>>(
  (ref) => ref.watch(apiProvider).helpdesk.listMailboxes(),
);

final _when = DateFormat('dd/MM/yyyy HH:mm');

const mailboxKinds = ['graph', 'imap_smtp'];

String mailboxKindLabel(BuildContext context, String kind) => switch (kind) {
  'graph' => context.l10n.mailboxKindGraph,
  _ => context.l10n.mailboxKindImap,
};

/// The mailboxes with when mail was last fetched and why it failed, and a dialog to add or
/// change one. Secrets are never entered here: a mailbox names the worker variable that holds it.
class MailboxesCard extends ConsumerWidget {
  const MailboxesCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final mailboxes = ref.watch(mailboxesProvider);
    Future<void> edit([Mailbox? m]) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => MailboxEditor(mailbox: m),
      );
      if (saved == true) ref.invalidate(mailboxesProvider);
    }

    return Card(
      key: const ValueKey('mailboxes'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(l.mailboxes, style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  key: const ValueKey('refresh-mailboxes'),
                  tooltip: l.mailboxRefresh,
                  onPressed: () => ref.invalidate(mailboxesProvider),
                  icon: const Icon(AppIcons.refresh),
                ),
                FilledButton.icon(
                  key: const ValueKey('new-mailbox'),
                  onPressed: edit,
                  icon: const Icon(AppIcons.add),
                  label: Text(l.newMailbox),
                ),
              ],
            ),
            mailboxes.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(errorMessage(e)),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(l.mailboxesEmpty),
                    )
                  : Column(
                      children: [
                        for (final m in list)
                          _MailboxTile(mailbox: m, onTap: () => edit(m)),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MailboxTile extends StatelessWidget {
  const _MailboxTile({required this.mailbox, required this.onTap});
  final Mailbox mailbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final m = mailbox;
    final failed = m.active && (m.lastError ?? '').isNotEmpty;
    // The state in words; the icon and colour only repeat it.
    final String status;
    if (!m.active) {
      status = l.inactive;
    } else if (failed) {
      status = l.mailboxError(m.lastError!);
    } else if (!m.inboundEnabled) {
      status = l.mailboxSendOnly;
    } else if (m.lastOkAt != null) {
      status = l.mailboxLastOk(_when.format(m.lastOkAt!.toLocal()));
    } else {
      status = l.mailboxNeverPolled;
    }
    return ListTile(
      key: ValueKey('mailbox-${m.id}'),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        failed ? AppIcons.warningAmber : AppIcons.mail,
        color: failed ? theme.colorScheme.error : null,
      ),
      title: Text(
        [m.name, if (m.isDefault) '(${l.mailboxDefaultBadge})'].join(' '),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              m.address,
              mailboxKindLabel(context, m.kind),
              if (m.teamName != null) m.teamName!,
            ].join(' · '),
          ),
          Text(
            status,
            key: ValueKey('mailbox-status-${m.id}'),
            style: failed ? TextStyle(color: theme.colorScheme.error) : null,
          ),
        ],
      ),
      isThreeLine: true,
      onTap: onTap,
    );
  }
}

/// Creates or edits a mailbox. The fields follow the kind of connection.
class MailboxEditor extends ConsumerStatefulWidget {
  const MailboxEditor({super.key, this.mailbox});
  final Mailbox? mailbox;

  @override
  ConsumerState<MailboxEditor> createState() => _MailboxEditorState();
}

class _MailboxEditorState extends ConsumerState<MailboxEditor> {
  Mailbox? get _m => widget.mailbox;
  late final _name = TextEditingController(text: _m?.name);
  late final _address = TextEditingController(text: _m?.address);
  late final _secretRef = TextEditingController(text: _m?.secretRef);
  late final _tenant = TextEditingController(text: _m?.tenantId);
  late final _client = TextEditingController(text: _m?.clientId);
  late final _username = TextEditingController(text: _m?.username);
  late final _imapHost = TextEditingController(text: _m?.imapHost);
  late final _imapPort = TextEditingController(text: _m?.imapPort?.toString());
  late final _imapFolder = TextEditingController(
    text: _m?.imapFolder ?? 'INBOX',
  );
  late final _smtpHost = TextEditingController(text: _m?.smtpHost);
  late final _smtpPort = TextEditingController(text: _m?.smtpPort?.toString());
  late String _kind = _m?.kind ?? 'graph';
  late String? _team = _m?.teamId;
  late bool _default = _m?.isDefault ?? false;
  late bool _active = _m?.active ?? true;
  late bool _inbound = _m?.inboundEnabled ?? true;
  late bool _imapTls = _m?.imapTls ?? true;
  late String _smtpSecurity = _m?.smtpSecurity ?? 'starttls';
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _secretRef,
      _tenant,
      _client,
      _username,
      _imapHost,
      _imapPort,
      _imapFolder,
      _smtpHost,
      _smtpPort,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _save() async {
    final graph = _kind == 'graph';
    final activeTeams = (ref.read(teamsProvider).value ?? const <Team>[])
        .where((t) => t.active);
    final teamId = activeTeams.any((t) => t.id == _team) ? _team : null;
    final input = MailboxInput(
      name: _name.text.trim(),
      address: _address.text.trim(),
      kind: _kind,
      secretRef: _secretRef.text.trim().toUpperCase(),
      teamId: teamId,
      isDefault: _default,
      active: _active,
      inboundEnabled: _inbound,
      tenantId: graph ? _text(_tenant) : null,
      clientId: graph ? _text(_client) : null,
      username: graph ? null : _text(_username),
      imapHost: graph ? null : _text(_imapHost),
      imapPort: graph ? null : int.tryParse(_imapPort.text.trim()),
      imapTls: _imapTls,
      imapFolder: graph ? null : _text(_imapFolder),
      smtpHost: graph ? null : _text(_smtpHost),
      smtpPort: graph ? null : int.tryParse(_smtpPort.text.trim()),
      smtpSecurity: graph ? null : _smtpSecurity,
    );
    try {
      final api = ref.read(apiProvider).helpdesk;
      if (_m == null) {
        await api.createMailbox(body: input);
      } else {
        await api.updateMailbox(id: _m!.id, body: input);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l.mailboxDeleteConfirm(_m!.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-mailbox'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(apiProvider).helpdesk.deleteMailbox(id: _m!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e));
    }
  }

  Widget _field(
    String key,
    TextEditingController controller,
    String label, {
    String? helper,
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: TextField(
      key: ValueKey(key),
      controller: controller,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final teams = (ref.watch(teamsProvider).value ?? const <Team>[])
        .where((t) => t.active)
        .toList();
    final graph = _kind == 'graph';
    final secretName = _secretRef.text.trim().toUpperCase();
    return AlertDialog(
      title: Text(_m == null ? l.newMailbox : _m!.name),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('mailbox-name', _name, l.name),
              _field('mailbox-address', _address, l.mailboxAddress),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('mailbox-kind'),
                isExpanded: true,
                initialValue: _kind,
                decoration: InputDecoration(labelText: l.mailboxKind),
                items: [
                  for (final k in mailboxKinds)
                    DropdownMenuItem(
                      value: k,
                      child: Text(mailboxKindLabel(context, k)),
                    ),
                ],
                onChanged: (v) => setState(() => _kind = v ?? _kind),
              ),
              if (graph) ...[
                _field('mailbox-tenant', _tenant, l.mailboxTenantId),
                _field('mailbox-client', _client, l.mailboxClientId),
              ] else ...[
                _field('mailbox-username', _username, l.mailboxUsername),
                _field('mailbox-imap-host', _imapHost, l.mailboxImapHost),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'mailbox-imap-port',
                        _imapPort,
                        l.mailboxImapPort,
                        number: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'mailbox-imap-folder',
                        _imapFolder,
                        l.mailboxImapFolder,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  key: const ValueKey('mailbox-imap-tls'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.mailboxImapTls),
                  value: _imapTls,
                  onChanged: (v) => setState(() => _imapTls = v),
                ),
                _field('mailbox-smtp-host', _smtpHost, l.mailboxSmtpHost),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: _field(
                        'mailbox-smtp-port',
                        _smtpPort,
                        l.mailboxSmtpPort,
                        number: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('mailbox-smtp-security'),
                        isExpanded: true,
                        initialValue: _smtpSecurity,
                        decoration: InputDecoration(
                          labelText: l.mailboxSmtpSecurity,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'starttls',
                            child: Text('STARTTLS'),
                          ),
                          const DropdownMenuItem(
                            value: 'tls',
                            child: Text('TLS'),
                          ),
                          DropdownMenuItem(
                            value: 'none',
                            child: Text(l.mailboxSmtpNone),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => _smtpSecurity = v ?? _smtpSecurity),
                      ),
                    ),
                  ],
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  key: const ValueKey('mailbox-secret-ref'),
                  controller: _secretRef,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l.mailboxSecretRef,
                    helperText: l.mailboxSecretHelp(
                      'MAILBOX_SECRET_${secretName.isEmpty ? 'SUPPORT' : secretName}',
                    ),
                    helperMaxLines: 3,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: ValueKey('mailbox-team-${teams.length}'),
                isExpanded: true,
                initialValue: teams.any((t) => t.id == _team) ? _team : null,
                decoration: InputDecoration(labelText: l.mailboxTeam),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l.mailboxTeamDefault),
                  ),
                  for (final t in teams)
                    DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) => setState(() => _team = v),
              ),
              SwitchListTile(
                key: const ValueKey('mailbox-inbound'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.mailboxInbound),
                value: _inbound,
                onChanged: (v) => setState(() => _inbound = v),
              ),
              SwitchListTile(
                key: const ValueKey('mailbox-default'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.mailboxDefault),
                value: _default,
                onChanged: (v) => setState(() => _default = v),
              ),
              SwitchListTile(
                key: const ValueKey('mailbox-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const ValueKey('mailbox-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (_m != null)
          TextButton(
            key: const ValueKey('delete-mailbox'),
            onPressed: _delete,
            child: Text(l.delete),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('save-mailbox'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
