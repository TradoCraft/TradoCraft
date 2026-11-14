import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../helpdesk/ticket_screen.dart' show usersProvider;
import 'reports_page.dart' show savedReportsProvider;

const scheduleFrequencies = ['daily', 'weekly', 'monthly'];
const schedulePeriods = [
  'yesterday',
  'last_7_days',
  'last_week',
  'last_30_days',
  'last_month',
];
const scheduleTables = [
  'volume',
  'backlog_status',
  'backlog_priority',
  'backlog_team',
  'backlog_owner',
  'times',
  'sla',
  'breaches_by_team',
  'top_categories',
  'top_tags',
  'time_by_user',
];

final reportSchedulesProvider =
    FutureProvider.autoDispose<List<ReportSchedule>>(
      (ref) => ref.watch(apiProvider).reports.reportSchedulesList(),
    );

extension _ScheduleLabels on AppLocalizations {
  String weekdayName(int d) => switch (d) {
    1 => rsMon,
    2 => rsTue,
    3 => rsWed,
    4 => rsThu,
    5 => rsFri,
    6 => rsSat,
    _ => rsSun,
  };

  String periodName(String p) => switch (p) {
    'yesterday' => rsPeriodYesterday,
    'last_7_days' => rsPeriodLast7,
    'last_week' => rsPeriodLastWeek,
    'last_30_days' => rsPeriodLast30,
    _ => rsPeriodLastMonth,
  };

  String frequencyName(String f) => switch (f) {
    'daily' => rsDaily,
    'weekly' => rsWeekly,
    _ => rsMonthly,
  };
}

/// "Weekly, Monday 07:30": when a schedule fires.
String scheduleWhen(AppLocalizations l, ReportSchedule s) =>
    switch (s.frequency) {
      'weekly' =>
        '${l.rsWeekly}, ${l.weekdayName(s.weekday ?? 1)} ${s.sendTime}',
      'monthly' => '${l.rsMonthly}, ${s.dayOfMonth ?? 1} · ${s.sendTime}',
      _ => '${l.rsDaily}, ${s.sendTime}',
    };

String _stamp(DateTime d) => DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());

/// Scheduled report mails (people with `reports.schedule`): list, pause, send now, edit, delete.
class ReportSchedulesPage extends ConsumerWidget {
  const ReportSchedulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final allowed = can(ref, 'reports.schedule');
    final schedules = allowed ? ref.watch(reportSchedulesProvider) : null;
    final api = ref.read(apiProvider).reports;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/reports'),
                icon: const Icon(AppIcons.arrowBack),
              ),
              Expanded(
                child: Text(l.rsTitle, style: theme.textTheme.headlineSmall),
              ),
              if (allowed)
                FilledButton.icon(
                  key: const ValueKey('new-schedule'),
                  icon: const Icon(AppIcons.add),
                  label: Text(l.rsNew),
                  onPressed: () async {
                    final saved = await showScheduleEditor(context);
                    if (saved == true) ref.invalidate(reportSchedulesProvider);
                  },
                ),
            ],
          ),
          if (!allowed)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.noPermission),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l.rsHelp, style: theme.textTheme.bodySmall),
            ),
            schedules!.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(errorMessage(e)),
              data: (list) => list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(l.rsEmpty),
                    )
                  : Column(
                      children: [
                        for (final s in list)
                          Card(
                            key: ValueKey('schedule-${s.id}'),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.name,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                        Text(
                                          s.source == 'custom'
                                              ? '${l.rsSourceCustom}: ${s.reportName ?? ''}'
                                              : '${l.rsSourceHelpdesk}: ${(s.helpdesk?.table ?? '').replaceAll('_', ' ')}, ${l.periodName(s.helpdesk?.period ?? '')}',
                                        ),
                                        Text(
                                          l.rsSummary(
                                            scheduleWhen(l, s),
                                            s.format.toUpperCase(),
                                            s.userIds.length +
                                                s.addresses.length,
                                          ),
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        Text(
                                          s.active
                                              ? l.rsNextRun(_stamp(s.nextRunAt))
                                              : l.rsPaused,
                                          style: theme.textTheme.bodySmall,
                                        ),
                                        if (s.lastStatus == 'sent')
                                          Text(
                                            l.rsLastSent(_stamp(s.lastRunAt!)),
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        if (s.lastStatus == 'failed')
                                          Text(
                                            l.rsLastFailed(
                                              _stamp(s.lastRunAt!),
                                              s.lastError ?? '',
                                            ),
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      theme.colorScheme.error,
                                                ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    key: ValueKey('schedule-active-${s.id}'),
                                    value: s.active,
                                    onChanged: (v) async {
                                      final ok = await runAction(
                                        context,
                                        () => api.reportSchedulesUpdate(
                                          id: s.id,
                                          body: scheduleInput(s, active: v),
                                        ),
                                      );
                                      if (ok) {
                                        ref.invalidate(reportSchedulesProvider);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    key: ValueKey('schedule-send-${s.id}'),
                                    tooltip: l.rsSendNow,
                                    icon: const Icon(AppIcons.send),
                                    onPressed: () async {
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final ok = await runAction(
                                        context,
                                        () async {
                                          final r = await api
                                              .reportSchedulesSend(id: s.id);
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                l.rsQueued(r.mails.toInt()),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                      if (ok) {
                                        ref.invalidate(reportSchedulesProvider);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    key: ValueKey('schedule-edit-${s.id}'),
                                    tooltip: l.edit,
                                    icon: const Icon(AppIcons.edit),
                                    onPressed: () async {
                                      final saved = await showScheduleEditor(
                                        context,
                                        schedule: s,
                                      );
                                      if (saved == true) {
                                        ref.invalidate(reportSchedulesProvider);
                                      }
                                    },
                                  ),
                                  IconButton(
                                    key: ValueKey('schedule-delete-${s.id}'),
                                    tooltip: l.remove,
                                    icon: const Icon(AppIcons.delete),
                                    onPressed: () async {
                                      final sure = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          title: Text(s.name),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(c, false),
                                              child: Text(l.cancel),
                                            ),
                                            FilledButton(
                                              key: const ValueKey(
                                                'schedule-confirm-delete',
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
                                        () =>
                                            api.reportSchedulesDelete(id: s.id),
                                      );
                                      if (ok) {
                                        ref.invalidate(reportSchedulesProvider);
                                      }
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
        ],
      ),
    );
  }
}

/// The input that re-saves a schedule, with the active switch changed.
ReportScheduleInput scheduleInput(ReportSchedule s, {bool? active}) =>
    ReportScheduleInput(
      name: s.name,
      source: s.source,
      reportId: s.reportId,
      helpdesk: s.helpdesk,
      frequency: s.frequency,
      weekday: s.weekday,
      dayOfMonth: s.dayOfMonth,
      sendTime: s.sendTime,
      timeZone: s.timeZone,
      format: s.format,
      userIds: s.userIds,
      addresses: s.addresses,
      active: active ?? s.active,
    );

/// Create or edit a schedule. Returns true when it was saved.
Future<bool?> showScheduleEditor(
  BuildContext context, {
  ReportSchedule? schedule,
}) => showDialog<bool>(
  context: context,
  builder: (_) => ScheduleEditor(schedule: schedule),
);

class ScheduleEditor extends ConsumerStatefulWidget {
  const ScheduleEditor({super.key, this.schedule});
  final ReportSchedule? schedule;

  @override
  ConsumerState<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends ConsumerState<ScheduleEditor> {
  late final _name = TextEditingController(text: widget.schedule?.name);
  late final _time = TextEditingController(
    text: widget.schedule?.sendTime ?? '07:00',
  );
  late final _day = TextEditingController(
    text: '${widget.schedule?.dayOfMonth ?? 1}',
  );
  late final _addresses = TextEditingController(
    text: (widget.schedule?.addresses ?? const []).join(', '),
  );
  late String _source = widget.schedule?.source ?? 'custom';
  late String? _reportId = widget.schedule?.reportId;
  late String _table = widget.schedule?.helpdesk?.table ?? 'volume';
  late String _period = widget.schedule?.helpdesk?.period ?? 'last_7_days';
  late String _frequency = widget.schedule?.frequency ?? 'weekly';
  late int _weekday = widget.schedule?.weekday ?? 1;
  late String _format = widget.schedule?.format ?? 'pdf';
  late bool _active = widget.schedule?.active ?? true;
  late final Set<String> _users = {...?widget.schedule?.userIds};
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final l = context.l10n;
    final addresses = [
      for (final a in _addresses.text.split(RegExp(r'[,;\s]+')))
        if (a.trim().isNotEmpty) a.trim(),
    ];
    if (_users.isEmpty && addresses.isEmpty) {
      setState(() => _error = l.rsNeedsRecipient);
      return;
    }
    final body = ReportScheduleInput(
      name: _name.text.trim(),
      source: _source,
      reportId: _source == 'custom' ? _reportId : null,
      helpdesk: _source == 'helpdesk'
          ? HelpdeskReportSpec(
              table: _table,
              period: _period,
              group: widget.schedule?.helpdesk?.group,
              category: widget.schedule?.helpdesk?.category,
              teamId: widget.schedule?.helpdesk?.teamId,
              ownerId: widget.schedule?.helpdesk?.ownerId,
            )
          : null,
      frequency: _frequency,
      weekday: _frequency == 'weekly' ? _weekday : null,
      dayOfMonth: _frequency == 'monthly'
          ? int.tryParse(_day.text.trim()) ?? 1
          : null,
      sendTime: _time.text.trim(),
      timeZone: widget.schedule?.timeZone,
      format: _format,
      userIds: _users.toList(),
      addresses: addresses,
      active: _active,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).reports;
      if (widget.schedule == null) {
        await api.reportSchedulesCreate(body: body);
      } else {
        await api.reportSchedulesUpdate(id: widget.schedule!.id, body: body);
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final reports = ref.watch(savedReportsProvider).value ?? const [];
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
    return AlertDialog(
      title: Text(widget.schedule == null ? l.rsNew : l.rsEdit),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('schedule-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.name),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('schedule-source'),
                initialValue: _source,
                isExpanded: true,
                decoration: InputDecoration(labelText: l.rsSource),
                items: [
                  DropdownMenuItem(
                    value: 'custom',
                    child: Text(l.rsSourceCustom),
                  ),
                  DropdownMenuItem(
                    value: 'helpdesk',
                    child: Text(l.rsSourceHelpdesk),
                  ),
                ],
                onChanged: (v) => setState(() => _source = v ?? 'custom'),
              ),
              if (_source == 'custom')
                DropdownButtonFormField<String>(
                  key: const ValueKey('schedule-report'),
                  initialValue: reports.any((r) => r.id == _reportId)
                      ? _reportId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.rsReport),
                  items: [
                    for (final r in reports)
                      DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => _reportId = v),
                )
              else ...[
                DropdownButtonFormField<String>(
                  key: const ValueKey('schedule-table'),
                  initialValue: _table,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.rsTable),
                  items: [
                    for (final t in scheduleTables)
                      DropdownMenuItem(
                        value: t,
                        child: Text(t.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: (v) => setState(() => _table = v ?? 'volume'),
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('schedule-period'),
                  initialValue: _period,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l.rsPeriod),
                  items: [
                    for (final p in schedulePeriods)
                      DropdownMenuItem(value: p, child: Text(l.periodName(p))),
                  ],
                  onChanged: (v) =>
                      setState(() => _period = v ?? 'last_7_days'),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('schedule-frequency'),
                      initialValue: _frequency,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l.rsFrequency),
                      items: [
                        for (final f in scheduleFrequencies)
                          DropdownMenuItem(
                            value: f,
                            child: Text(l.frequencyName(f)),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _frequency = v ?? 'weekly'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_frequency == 'weekly')
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('schedule-weekday'),
                        initialValue: _weekday,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l.rsWeekday),
                        items: [
                          for (var d = 1; d <= 7; d++)
                            DropdownMenuItem(
                              value: d,
                              child: Text(l.weekdayName(d)),
                            ),
                        ],
                        onChanged: (v) => setState(() => _weekday = v ?? 1),
                      ),
                    ),
                  if (_frequency == 'monthly')
                    Expanded(
                      child: TextField(
                        key: const ValueKey('schedule-day'),
                        controller: _day,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: l.rsDayOfMonth),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('schedule-time'),
                      controller: _time,
                      decoration: InputDecoration(labelText: l.rsTime),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l.rsFormat, style: theme.textTheme.labelMedium),
              SegmentedButton<String>(
                key: const ValueKey('schedule-format'),
                segments: const [
                  ButtonSegment(value: 'csv', label: Text('CSV')),
                  ButtonSegment(value: 'pdf', label: Text('PDF')),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              const SizedBox(height: 8),
              Text(l.rsColleagues, style: theme.textTheme.labelMedium),
              Wrap(
                spacing: 6,
                children: [
                  for (final u in users)
                    FilterChip(
                      key: ValueKey('schedule-user-${u.id}'),
                      label: Text(u.displayName),
                      selected: _users.contains(u.id),
                      onSelected: (on) => setState(
                        () => on ? _users.add(u.id) : _users.remove(u.id),
                      ),
                    ),
                ],
              ),
              TextField(
                key: const ValueKey('schedule-addresses'),
                controller: _addresses,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l.rsAddresses),
              ),
              SwitchListTile(
                key: const ValueKey('schedule-active'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
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
          key: const ValueKey('save-schedule'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}
