import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import 'helpdesk_mailboxes.dart';
import 'sla_notices_card.dart';
import 'ticket_screen.dart' show teamsProvider, usersProvider;
import 'tickets_page.dart' show ticketPriorities;
import '../../shared/app_icons.dart';

final _policiesProvider = FutureProvider.autoDispose<List<SlaPolicy>>(
  (ref) => ref.watch(apiProvider).helpdesk.getPolicies(),
);

final _settingsProvider = FutureProvider.autoDispose<HelpdeskSettings>(
  (ref) => ref.watch(apiProvider).helpdesk.getSettings(),
);

/// Helpdesk administration: service levels per priority, teams and their members, the
/// mailboxes, and the default team and satisfaction survey switch.
class HelpdeskSettingsPage extends ConsumerWidget {
  const HelpdeskSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final canAdmin =
        ref.watch(meProvider).value?.permissions.contains('helpdesk.admin') ??
        false;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/helpdesk'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(
                l.helpdeskSettings,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
          ),
          if (!canAdmin)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.noPermission),
            )
          else ...[
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('open-calendar'),
                  icon: const Icon(AppIcons.schedule),
                  label: Text(l.businessHours),
                  onPressed: () => context.push('/helpdesk/calendar'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('open-automation'),
                  icon: const Icon(AppIcons.autoFixHigh),
                  label: Text(l.automationRules),
                  onPressed: () => context.push('/helpdesk/automation'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _PoliciesCard(),
            const SizedBox(height: 16),
            const SlaNoticesCard(),
            const SizedBox(height: 16),
            const _TeamsCard(),
            const SizedBox(height: 16),
            const MailboxesCard(),
            const SizedBox(height: 16),
            const _SettingsCard(),
          ],
        ],
      ),
    );
  }
}

class _PoliciesCard extends ConsumerStatefulWidget {
  const _PoliciesCard();

  @override
  ConsumerState<_PoliciesCard> createState() => _PoliciesCardState();
}

class _PoliciesCardState extends ConsumerState<_PoliciesCard> {
  final _first = <String, TextEditingController>{};
  final _resolution = <String, TextEditingController>{};
  bool _filled = false;

  void _fill(List<SlaPolicy> policies) {
    if (_filled) return;
    _filled = true;
    for (final p in policies) {
      _first[p.priority] = TextEditingController(
        text: '${p.firstResponseMinutes}',
      );
      _resolution[p.priority] = TextEditingController(
        text: '${p.resolutionMinutes}',
      );
    }
  }

  Future<void> _save() => runAction(context, () async {
    final policies = <SlaPolicy>[];
    for (final p in ticketPriorities) {
      final f = int.tryParse(_first[p]?.text.trim() ?? '');
      final r = int.tryParse(_resolution[p]?.text.trim() ?? '');
      if (f == null || r == null) continue;
      policies.add(
        SlaPolicy(priority: p, firstResponseMinutes: f, resolutionMinutes: r),
      );
    }
    await ref
        .read(apiProvider)
        .helpdesk
        .putPolicies(body: SlaPoliciesInput(policies: policies));
    ref.invalidate(_policiesProvider);
  }, success: context.l10n.saved);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final policies = ref.watch(_policiesProvider);
    return Card(
      key: const ValueKey('sla-policies'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: policies.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) {
            _fill(list);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.slaPolicies, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(l.slaPoliciesHelp, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final p in ticketPriorities.reversed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 120, child: Text(l.ticketPriority(p))),
                        Expanded(
                          child: TextField(
                            key: ValueKey('first-$p'),
                            controller: _first[p],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l.firstResponseMinutes,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            key: ValueKey('resolution-$p'),
                            controller: _resolution[p],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: l.resolutionMinutes,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    key: const ValueKey('save-policies'),
                    onPressed: _save,
                    child: Text(l.save),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TeamsCard extends ConsumerWidget {
  const _TeamsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final teams = ref.watch(teamsProvider);
    Future<void> edit([Team? t]) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => TeamEditor(team: t),
      );
      if (saved == true) {
        ref.invalidate(teamsProvider);
        ref.invalidate(_settingsProvider);
      }
    }

    return Card(
      key: const ValueKey('teams'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(l.teams, style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  key: const ValueKey('new-team'),
                  onPressed: edit,
                  icon: const Icon(AppIcons.add),
                  label: Text(l.newTeam),
                ),
              ],
            ),
            teams.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(errorMessage(e)),
              data: (list) => Column(
                children: [
                  for (final t in list)
                    ListTile(
                      key: ValueKey('team-${t.id}'),
                      title: Text(t.name),
                      subtitle: Text(
                        [
                          if (!t.active) l.inactive,
                          for (final m in t.members)
                            m.isLead
                                ? '${m.displayName} (${l.teamLead})'
                                : m.displayName,
                        ].join(' · '),
                      ),
                      onTap: () => edit(t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Creates or edits a team: name, active, members and who leads.
class TeamEditor extends ConsumerStatefulWidget {
  const TeamEditor({super.key, this.team});
  final Team? team;

  @override
  ConsumerState<TeamEditor> createState() => _TeamEditorState();
}

class _TeamEditorState extends ConsumerState<TeamEditor> {
  late final _name = TextEditingController(text: widget.team?.name);
  late bool _active = widget.team?.active ?? true;
  late final Map<String, bool> _members = {
    for (final m in widget.team?.members ?? const <TeamMember>[])
      m.userId: m.isLead,
  };
  String? _error;

  Future<void> _save() async {
    final input = TeamInput(
      name: _name.text.trim(),
      active: _active,
      members: [
        for (final e in _members.entries)
          MemberInput(userId: e.key, isLead: e.value),
      ],
    );
    try {
      final api = ref.read(apiProvider).helpdesk;
      if (widget.team == null) {
        await api.createTeam(body: input);
      } else {
        await api.updateTeam(id: widget.team!.id, body: input);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
    return AlertDialog(
      title: Text(widget.team == null ? l.newTeam : widget.team!.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('team-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.teamName),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              Text(
                l.teamMembers,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final u in users)
                CheckboxListTile(
                  key: ValueKey('member-${u.id}'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(u.displayName),
                  subtitle: _members.containsKey(u.id)
                      ? Row(
                          children: [
                            Text(l.teamLead),
                            Switch(
                              key: ValueKey('lead-${u.id}'),
                              value: _members[u.id] ?? false,
                              onChanged: (v) =>
                                  setState(() => _members[u.id] = v),
                            ),
                          ],
                        )
                      : null,
                  value: _members.containsKey(u.id),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _members[u.id] = false;
                    } else {
                      _members.remove(u.id);
                    }
                  }),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('save-team'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

class _SettingsCard extends ConsumerStatefulWidget {
  const _SettingsCard();

  @override
  ConsumerState<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends ConsumerState<_SettingsCard> {
  String? _team;
  bool _csat = false;
  bool _filled = false;

  Future<void> _save() => runAction(context, () async {
    await ref
        .read(apiProvider)
        .helpdesk
        .putSettings(
          body: SettingsInput(defaultTeamId: _team, csatEnabled: _csat),
        );
    ref.invalidate(_settingsProvider);
  }, success: context.l10n.saved);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final settings = ref.watch(_settingsProvider);
    final teams = (ref.watch(teamsProvider).value ?? const <Team>[])
        .where((t) => t.active)
        .toList();
    settings.whenData((s) {
      if (_filled) return;
      _filled = true;
      _team = s.defaultTeamId;
      _csat = s.csatEnabled;
    });
    return Card(
      key: const ValueKey('helpdesk-settings'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String?>(
              key: ValueKey('default-team-${teams.length}-$_team-$_filled'),
              isExpanded: true,
              initialValue: teams.any((t) => t.id == _team) ? _team : null,
              decoration: InputDecoration(labelText: l.defaultTeam),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text(l.noTeam)),
                for (final t in teams)
                  DropdownMenuItem<String?>(value: t.id, child: Text(t.name)),
              ],
              onChanged: (v) => setState(() => _team = v),
            ),
            SwitchListTile(
              key: const ValueKey('csat-enabled'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.csatEnabled),
              value: _csat,
              onChanged: (v) => setState(() => _csat = v),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('save-settings'),
                onPressed: _save,
                child: Text(l.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
