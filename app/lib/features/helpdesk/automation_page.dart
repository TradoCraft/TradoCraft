import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/search_picker.dart';
import 'ticket_screen.dart' show teamsProvider, usersProvider;
import '../../shared/app_icons.dart';
import 'tickets_page.dart'
    show ticketCategories, ticketPriorities, ticketStatuses;

const ruleTriggers = ['created', 'updated', 'customer_replied'];
const ruleChannels = ['email', 'portal', 'phone', 'manual', 'internal'];
const ruleLanguages = ['nl', 'fr', 'en', 'de', 'es'];
const actionKinds = [
  'set_owner',
  'set_team',
  'set_priority',
  'set_category',
  'add_tag',
  'set_internal',
];

final _rulesProvider = FutureProvider.autoDispose<List<Rule>>(
  (ref) => ref.watch(apiProvider).helpdesk.listRules(),
);

extension _RuleLabels on AppLocalizations {
  String triggerName(String t) => switch (t) {
    'created' => ruleTriggerCreated,
    'updated' => ruleTriggerUpdated,
    _ => ruleTriggerCustomerReplied,
  };

  String channelName(String c) => switch (c) {
    'email' => channelEmail,
    'portal' => channelPortal,
    'phone' => channelPhone,
    'manual' => channelManual,
    _ => channelInternal,
  };

  String actionKind(String k) => switch (k) {
    'set_owner' => actionSetOwner,
    'set_team' => actionSetTeam,
    'set_priority' => actionSetPriority,
    'set_category' => actionSetCategory,
    'add_tag' => actionAddTag,
    _ => actionSetInternal,
  };

  String ruleResult(String r) => switch (r) {
    'matched' => ruleResultMatched,
    'no_match' => ruleResultNoMatch,
    'inactive' => ruleResultInactive,
    'after_stop' => ruleResultAfterStop,
    _ => ruleResultOtherTrigger,
  };
}

/// One line per condition and per action, for the rule list.
List<String> ruleSummary(
  AppLocalizations l,
  Rule r, {
  Map<String, String> teams = const {},
  Map<String, String> users = const {},
}) {
  final c = r.conditions;
  String join(Iterable<String> v) => v.join(', ');
  return [
    if (c.priorities?.isNotEmpty ?? false)
      '${l.priority}: ${join(c.priorities!.map(l.ticketPriority))}',
    if (c.categories?.isNotEmpty ?? false)
      '${l.category}: ${join(c.categories!.map(l.ticketCategory))}',
    if (c.statuses?.isNotEmpty ?? false)
      '${l.status}: ${join(c.statuses!.map(l.ticketStatus))}',
    if (c.customerLanguages?.isNotEmpty ?? false)
      '${l.customerLanguage}: ${join(c.customerLanguages!.map(languageName))}',
    if (c.channels?.isNotEmpty ?? false)
      '${l.channel}: ${join(c.channels!.map(l.channelName))}',
    if (c.subjectContains?.isNotEmpty ?? false)
      '${l.subject} ∋ "${c.subjectContains}"',
    if (c.senderDomain?.isNotEmpty ?? false)
      '${l.senderDomain}: ${c.senderDomain}',
    if (c.tag?.isNotEmpty ?? false) '${l.tag}: ${c.tag}',
    if (c.teamId != null) '${l.team}: ${teams[c.teamId] ?? '…'}',
    if (c.customerId != null) '${l.customer}: …',
    if (c.owner == 'empty') '${l.owner}: ${l.ownerEmpty}',
    if (c.owner == 'set') '${l.owner}: ${l.ownerSet}',
    for (final a in r.actions)
      switch (a.kind) {
        'set_owner' => '→ ${l.actionSetOwner}: ${users[a.userId] ?? '…'}',
        'set_team' => '→ ${l.actionSetTeam}: ${teams[a.teamId] ?? '…'}',
        'set_priority' =>
          '→ ${l.actionSetPriority}: ${l.ticketPriority(a.value ?? '')}',
        'set_category' =>
          '→ ${l.actionSetCategory}: ${l.ticketCategory(a.value ?? '')}',
        'add_tag' => '→ ${l.actionAddTag}: ${a.value}',
        _ => '→ ${l.actionSetInternal}: ${a.flag == true ? l.yes : l.no}',
      },
  ];
}

/// Automation rules: create, reorder, switch on and off, delete, and try them on a ticket.
class AutomationPage extends ConsumerWidget {
  const AutomationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final canAdmin =
        ref.watch(meProvider).value?.permissions.contains('helpdesk.admin') ??
        false;
    final rules = ref.watch(_rulesProvider);
    final teams = {
      for (final t in ref.watch(teamsProvider).value ?? const <Team>[])
        t.id: t.name,
    };
    final users = {
      for (final u in ref.watch(usersProvider).value ?? const <CompanyUser>[])
        u.id: u.displayName,
    };
    final api = ref.read(apiProvider).helpdesk;

    Future<void> move(List<Rule> list, int from, int to) async {
      final ids = [for (final r in list) r.id];
      ids.insert(to, ids.removeAt(from));
      final ok = await runAction(
        context,
        () => api.reorderRules(body: RuleOrder(ids: ids)),
      );
      if (ok) ref.invalidate(_rulesProvider);
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/helpdesk/settings'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Text(
                l.automationRules,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (canAdmin) ...[
                FilledButton.icon(
                  key: const ValueKey('new-rule'),
                  icon: const Icon(AppIcons.add),
                  label: Text(l.newRule),
                  onPressed: () async {
                    if (await showRuleEditor(context) == true) {
                      ref.invalidate(_rulesProvider);
                    }
                  },
                ),
                OutlinedButton.icon(
                  key: const ValueKey('dry-run'),
                  icon: const Icon(AppIcons.science),
                  label: Text(l.dryRun),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _DryRunDialog(),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(l.automationHelp, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          if (!canAdmin)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.noPermission),
            )
          else
            rules.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(errorMessage(e)),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(l.noRules),
                    )
                  : Column(
                      children: [
                        for (var i = 0; i < list.length; i++)
                          Card(
                            key: ValueKey('rule-${list[i].id}'),
                            child: ListTile(
                              leading: CircleAvatar(
                                radius: 14,
                                child: Text('${i + 1}'),
                              ),
                              title: Text(list[i].name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${l.triggerName(list[i].trigger)}'
                                    '${list[i].stopOnMatch ? ' · ${l.stopOnMatch}' : ''}',
                                  ),
                                  for (final line in ruleSummary(
                                    l,
                                    list[i],
                                    teams: teams,
                                    users: users,
                                  ))
                                    Text(line),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  IconButton(
                                    key: ValueKey('up-$i'),
                                    tooltip: l.moveUp,
                                    icon: const Icon(AppIcons.arrowUpward),
                                    onPressed: i == 0
                                        ? null
                                        : () => move(list, i, i - 1),
                                  ),
                                  IconButton(
                                    key: ValueKey('down-$i'),
                                    tooltip: l.moveDown,
                                    icon: const Icon(AppIcons.arrowDownward),
                                    onPressed: i == list.length - 1
                                        ? null
                                        : () => move(list, i, i + 1),
                                  ),
                                  Switch(
                                    key: ValueKey('active-$i'),
                                    value: list[i].active,
                                    onChanged: (v) async {
                                      final r = list[i];
                                      final ok = await runAction(
                                        context,
                                        () => api.updateRule(
                                          id: r.id,
                                          body: RuleInput(
                                            name: r.name,
                                            trigger: r.trigger,
                                            conditions: r.conditions,
                                            actions: r.actions,
                                            stopOnMatch: r.stopOnMatch,
                                            active: v,
                                          ),
                                        ),
                                      );
                                      if (ok) ref.invalidate(_rulesProvider);
                                    },
                                  ),
                                  IconButton(
                                    key: ValueKey('edit-$i'),
                                    tooltip: l.edit,
                                    icon: const Icon(AppIcons.edit),
                                    onPressed: () async {
                                      if (await showRuleEditor(
                                            context,
                                            rule: list[i],
                                          ) ==
                                          true) {
                                        ref.invalidate(_rulesProvider);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    key: ValueKey('delete-$i'),
                                    tooltip: l.remove,
                                    icon: const Icon(AppIcons.delete),
                                    onPressed: () async {
                                      final sure = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: Text(list[i].name),
                                          content: Text(l.deleteRuleConfirm),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: Text(l.cancel),
                                            ),
                                            FilledButton(
                                              key: const ValueKey(
                                                'confirm-delete-rule',
                                              ),
                                              onPressed: () =>
                                                  Navigator.pop(c, true),
                                              child: Text(l.remove),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (sure != true || !context.mounted) {
                                        return;
                                      }
                                      final ok = await runAction(
                                        context,
                                        () => api.deleteRule(id: list[i].id),
                                      );
                                      if (ok) ref.invalidate(_rulesProvider);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// Create or edit a rule. Returns true when it was saved.
Future<bool?> showRuleEditor(BuildContext context, {Rule? rule}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => RuleEditor(rule: rule),
    );

class RuleEditor extends ConsumerStatefulWidget {
  const RuleEditor({super.key, this.rule});
  final Rule? rule;

  @override
  ConsumerState<RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends ConsumerState<RuleEditor> {
  late final _name = TextEditingController(text: widget.rule?.name);
  late final _subject = TextEditingController(
    text: widget.rule?.conditions.subjectContains,
  );
  late final _domain = TextEditingController(
    text: widget.rule?.conditions.senderDomain,
  );
  late final _tag = TextEditingController(text: widget.rule?.conditions.tag);
  late String _trigger = widget.rule?.trigger ?? 'created';
  late bool _active = widget.rule?.active ?? true;
  late bool _stop = widget.rule?.stopOnMatch ?? false;
  late final Set<String> _priorities = {...?widget.rule?.conditions.priorities};
  late final Set<String> _categories = {...?widget.rule?.conditions.categories};
  late final Set<String> _statuses = {...?widget.rule?.conditions.statuses};
  late final Set<String> _languages = {
    ...?widget.rule?.conditions.customerLanguages,
  };
  late final Set<String> _channels = {...?widget.rule?.conditions.channels};
  late String? _teamId = widget.rule?.conditions.teamId;
  late String? _owner = widget.rule?.conditions.owner;
  late String? _customerId = widget.rule?.conditions.customerId;
  String? _customerName;
  late final List<RuleAction> _actions = [...?widget.rule?.actions];
  final _actionTexts = <int, TextEditingController>{};
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _actions.length; i++) {
      if (_actions[i].kind == 'add_tag') {
        _actionTexts[i] = TextEditingController(text: _actions[i].value);
      }
    }
  }

  Future<void> _save() async {
    final l = context.l10n;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = l.ruleNameRequired);
      return;
    }
    final actions = <RuleAction>[];
    for (var i = 0; i < _actions.length; i++) {
      final a = _actions[i];
      actions.add(
        a.kind == 'add_tag'
            ? RuleAction(kind: a.kind, value: _actionTexts[i]?.text.trim())
            : a,
      );
    }
    String? text(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final body = RuleInput(
      name: _name.text.trim(),
      active: _active,
      trigger: _trigger,
      stopOnMatch: _stop,
      conditions: RuleConditions(
        priorities: _priorities.toList(),
        categories: _categories.toList(),
        statuses: _statuses.toList(),
        customerLanguages: _languages.toList(),
        channels: _channels.toList(),
        customerId: _customerId,
        subjectContains: text(_subject),
        senderDomain: text(_domain),
        tag: text(_tag),
        teamId: _teamId,
        owner: _owner,
      ),
      actions: actions,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).helpdesk;
      if (widget.rule == null) {
        await api.createRule(body: body);
      } else {
        await api.updateRule(id: widget.rule!.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorMessage(e);
        });
      }
    }
  }

  Widget _chips(
    String label,
    List<String> values,
    Set<String> selected,
    String Function(String) name,
    String keyPrefix,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Wrap(
          spacing: 6,
          children: [
            for (final v in values)
              FilterChip(
                key: ValueKey('$keyPrefix-$v'),
                label: Text(name(v)),
                selected: selected.contains(v),
                onSelected: (on) =>
                    setState(() => on ? selected.add(v) : selected.remove(v)),
              ),
          ],
        ),
      ],
    ),
  );

  Widget _actionRow(int i, List<Team> teams, List<CompanyUser> users) {
    final l = context.l10n;
    final a = _actions[i];
    Widget value;
    switch (a.kind) {
      case 'set_owner':
        value = DropdownButtonFormField<String>(
          key: ValueKey('action-value-$i'),
          initialValue: users.any((u) => u.id == a.userId) ? a.userId : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.owner, isDense: true),
          items: [
            for (final u in users)
              DropdownMenuItem(value: u.id, child: Text(u.displayName)),
          ],
          onChanged: (v) =>
              setState(() => _actions[i] = RuleAction(kind: a.kind, userId: v)),
        );
      case 'set_team':
        value = DropdownButtonFormField<String>(
          key: ValueKey('action-value-$i'),
          initialValue: teams.any((t) => t.id == a.teamId) ? a.teamId : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: l.team, isDense: true),
          items: [
            for (final t in teams.where((t) => t.active))
              DropdownMenuItem(value: t.id, child: Text(t.name)),
          ],
          onChanged: (v) =>
              setState(() => _actions[i] = RuleAction(kind: a.kind, teamId: v)),
        );
      case 'set_priority':
      case 'set_category':
        final priority = a.kind == 'set_priority';
        final values = priority ? ticketPriorities : ticketCategories;
        value = DropdownButtonFormField<String>(
          key: ValueKey('action-value-$i'),
          initialValue: values.contains(a.value) ? a.value : null,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: priority ? l.priority : l.category,
            isDense: true,
          ),
          items: [
            for (final v in values)
              DropdownMenuItem(
                value: v,
                child: Text(
                  priority ? l.ticketPriority(v) : l.ticketCategory(v),
                ),
              ),
          ],
          onChanged: (v) =>
              setState(() => _actions[i] = RuleAction(kind: a.kind, value: v)),
        );
      case 'add_tag':
        value = TextField(
          key: ValueKey('action-value-$i'),
          controller: _actionTexts.putIfAbsent(
            i,
            () => TextEditingController(text: a.value),
          ),
          decoration: InputDecoration(labelText: l.tag, isDense: true),
        );
      default:
        value = SwitchListTile(
          key: ValueKey('action-value-$i'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l.actionSetInternal),
          value: a.flag ?? false,
          onChanged: (v) =>
              setState(() => _actions[i] = RuleAction(kind: a.kind, flag: v)),
        );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              key: ValueKey('action-kind-$i'),
              initialValue: a.kind,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.action, isDense: true),
              items: [
                for (final k in actionKinds)
                  DropdownMenuItem(value: k, child: Text(l.actionKind(k))),
              ],
              onChanged: (k) => setState(() {
                _actionTexts.remove(i);
                _actions[i] = RuleAction(
                  kind: k!,
                  flag: k == 'set_internal' ? true : null,
                );
              }),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: value),
          IconButton(
            tooltip: l.remove,
            icon: const Icon(AppIcons.close),
            onPressed: () => setState(() {
              _actions.removeAt(i);
              _actionTexts.clear();
              for (var j = 0; j < _actions.length; j++) {
                if (_actions[j].kind == 'add_tag') {
                  _actionTexts[j] = TextEditingController(
                    text: _actions[j].value,
                  );
                }
              }
            }),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
    return AlertDialog(
      title: Text(widget.rule == null ? l.newRule : widget.rule!.name),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('rule-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.name),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('rule-trigger'),
                      initialValue: _trigger,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.ruleTrigger),
                      items: [
                        for (final t in ruleTriggers)
                          DropdownMenuItem(
                            value: t,
                            child: Text(l.triggerName(t)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _trigger = v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(l.active),
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('rule-stop'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(l.stopOnMatch),
                subtitle: Text(l.stopOnMatchHelp),
                value: _stop,
                onChanged: (v) => setState(() => _stop = v),
              ),
              const Divider(),
              Text(l.ruleConditions, style: theme.textTheme.titleSmall),
              Text(l.ruleConditionsHelp, style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              _chips(
                l.priority,
                ticketPriorities,
                _priorities,
                l.ticketPriority,
                'cond-priority',
              ),
              _chips(
                l.category,
                ticketCategories,
                _categories,
                l.ticketCategory,
                'cond-category',
              ),
              _chips(
                l.status,
                ticketStatuses,
                _statuses,
                l.ticketStatus,
                'cond-status',
              ),
              _chips(
                l.customerLanguage,
                ruleLanguages,
                _languages,
                languageName,
                'cond-language',
              ),
              _chips(
                l.channel,
                ruleChannels,
                _channels,
                l.channelName,
                'cond-channel',
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('cond-subject'),
                      controller: _subject,
                      decoration: InputDecoration(
                        labelText: l.subjectContains,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('cond-domain'),
                      controller: _domain,
                      decoration: InputDecoration(
                        labelText: l.senderDomain,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('cond-tag'),
                      controller: _tag,
                      decoration: InputDecoration(
                        labelText: l.tag,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: const ValueKey('cond-team'),
                      initialValue: teams.any((t) => t.id == _teamId)
                          ? _teamId
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.team,
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l.anyValue),
                        ),
                        for (final t in teams)
                          DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.name),
                          ),
                      ],
                      onChanged: (v) => setState(() => _teamId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      key: const ValueKey('cond-owner'),
                      initialValue: _owner,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l.owner,
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l.anyValue),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'empty',
                          child: Text(l.ownerEmpty),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'set',
                          child: Text(l.ownerSet),
                        ),
                      ],
                      onChanged: (v) => setState(() => _owner = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_customerId != null)
                InputChip(
                  label: Text('${l.customer}: ${_customerName ?? '…'}'),
                  onDeleted: () => setState(() => _customerId = null),
                )
              else
                SearchPicker<Customer>(
                  label: l.customerOptional,
                  display: (c) => '${c.code} · ${c.name}',
                  search: (q) async =>
                      (await ref
                              .read(apiProvider)
                              .crm
                              .listCustomers(q: q, limit: 20))
                          .items,
                  onSelected: (c) => setState(() {
                    _customerId = c.id;
                    _customerName = c.name;
                  }),
                ),
              const Divider(),
              Text(l.ruleActions, style: theme.textTheme.titleSmall),
              for (var i = 0; i < _actions.length; i++)
                _actionRow(i, teams, users),
              TextButton.icon(
                key: const ValueKey('add-action'),
                icon: const Icon(AppIcons.add),
                label: Text(l.addAction),
                onPressed: () => setState(
                  () => _actions.add(RuleAction(kind: 'set_priority')),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('save-rule'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

class _DryRunDialog extends ConsumerStatefulWidget {
  const _DryRunDialog();

  @override
  ConsumerState<_DryRunDialog> createState() => _DryRunDialogState();
}

class _DryRunDialogState extends ConsumerState<_DryRunDialog> {
  Ticket? _ticket;
  String _trigger = 'created';
  DryRun? _result;
  String? _error;
  bool _busy = false;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref
          .read(apiProvider)
          .helpdesk
          .dryRun(
            body: DryRunInput(ticketId: _ticket!.id, trigger: _trigger),
          );
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _change(AppLocalizations l, RuleChange c) =>
      '${l.actionKind(c.kind)}: ${c.from ?? '—'} → ${c.to ?? '—'}';

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.dryRun),
      content: SizedBox(
        width: 560,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.dryRunHelp),
            const SizedBox(height: 8),
            SearchPicker<Ticket>(
              label: l.ticket,
              display: (t) => '${t.number} · ${t.subject}',
              search: (q) async =>
                  (await ref
                          .read(apiProvider)
                          .helpdesk
                          .listTickets(q: q, limit: 20))
                      .items,
              onSelected: (t) => setState(() {
                _ticket = t;
                _result = null;
              }),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _trigger,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: l.ruleTrigger),
                    items: [
                      for (final t in ruleTriggers)
                        DropdownMenuItem(
                          value: t,
                          child: Text(l.triggerName(t)),
                        ),
                    ],
                    onChanged: (v) => setState(() {
                      _trigger = v!;
                      _result = null;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  key: const ValueKey('run-dry-run'),
                  onPressed: _ticket == null || _busy ? null : _run,
                  child: Text(l.dryRunRun),
                ),
              ],
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (_result != null)
                    for (final o in _result!.rules)
                      ListTile(
                        key: ValueKey('outcome-${o.ruleId}'),
                        dense: true,
                        title: Text(o.ruleName),
                        subtitle: o.changes.isEmpty
                            ? null
                            : Text(
                                o.changes.map((c) => _change(l, c)).join('\n'),
                              ),
                        trailing: Chip(
                          label: Text(l.ruleResult(o.result)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
