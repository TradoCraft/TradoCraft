import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';
import 'report_charts.dart';
import 'ticket_screen.dart' show teamsProvider, usersProvider;
import 'tickets_page.dart' show ticketCategories;
import '../../shared/app_icons.dart';

/// Read-only helpdesk report: volume, backlog, response times, SLA, satisfaction, top lists and
/// logged time, with filters and a CSV export of every table.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  late DateTime _to = _today();
  late DateTime _from = _to.subtract(const Duration(days: 29));
  String _group = 'day';
  String? _team, _owner, _category;
  late Future<Report> _report = _load();

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<Report> _load() => ref
      .read(apiProvider)
      .helpdesk
      .getReport(
        from: _from,
        to: _to,
        group: _group,
        teamId: _team,
        ownerId: _owner,
        category: _category,
      );

  void _reload() => setState(() {
    _report = _load();
  });

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    _from = from ? d : _from;
    _to = from ? _to : d;
    _reload();
  }

  void _preset(int days) {
    _to = _today();
    _from = _to.subtract(Duration(days: days - 1));
    _reload();
  }

  /// Puts one table on the clipboard as CSV.
  Future<void> _csv(String table) async {
    final l = context.l10n;
    final ok = await runAction(context, () async {
      final text = await ref
          .read(apiProvider)
          .helpdesk
          .exportReport(
            table: table,
            from: _from,
            to: _to,
            group: _group,
            teamId: _team,
            ownerId: _owner,
            category: _category,
          );
      await Clipboard.setData(ClipboardData(text: text));
    }, success: l.csvCopied);
    if (!ok) return;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final teams = ref.watch(teamsProvider).value ?? const <Team>[];
    final users = ref.watch(usersProvider).value ?? const <CompanyUser>[];
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
              Text(l.helpdeskReports, style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const ValueKey('report-from'),
                onPressed: () => _pick(true),
                child: Text('${l.from}: ${date(_from)}'),
              ),
              OutlinedButton(
                key: const ValueKey('report-to'),
                onPressed: () => _pick(false),
                child: Text('${l.to}: ${date(_to)}'),
              ),
              for (final days in const [7, 30, 90])
                ActionChip(
                  key: ValueKey('preset-$days'),
                  label: Text(l.lastDays(days)),
                  onPressed: () => _preset(days),
                ),
              SegmentedButton<String>(
                key: const ValueKey('report-group'),
                segments: [
                  ButtonSegment(value: 'day', label: Text(l.perDay)),
                  ButtonSegment(value: 'week', label: Text(l.perWeek)),
                ],
                selected: {_group},
                onSelectionChanged: (s) {
                  _group = s.first;
                  _reload();
                },
              ),
              DropdownButton<String?>(
                key: const ValueKey('report-team'),
                value: teams.any((t) => t.id == _team) ? _team : null,
                hint: Text(l.allTeams),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.allTeams)),
                  for (final t in teams)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: (v) {
                  _team = v;
                  _reload();
                },
              ),
              DropdownButton<String?>(
                key: const ValueKey('report-owner'),
                value: users.any((u) => u.id == _owner) ? _owner : null,
                hint: Text(l.allOwners),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.allOwners)),
                  for (final u in users)
                    DropdownMenuItem(value: u.id, child: Text(u.displayName)),
                ],
                onChanged: (v) {
                  _owner = v;
                  _reload();
                },
              ),
              DropdownButton<String?>(
                key: const ValueKey('report-category'),
                value: _category,
                hint: Text(l.allCategories),
                items: [
                  DropdownMenuItem(value: null, child: Text(l.allCategories)),
                  for (final c in ticketCategories)
                    DropdownMenuItem(
                      value: c,
                      child: Text(l.ticketCategory(c)),
                    ),
                ],
                onChanged: (v) {
                  _category = v;
                  _reload();
                },
              ),
            ],
          ),
          FutureBuilder<Report>(
            future: _report,
            builder: (context, snap) {
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(errorMessage(snap.error!)),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: LinearProgressIndicator(),
                );
              }
              return _body(context, snap.data!);
            },
          ),
        ],
      ),
    );
  }

  String _minutes(double? m) => m == null ? '—' : minutesText(m.round());

  String _percent(double? p) => p == null ? '—' : '${number(p.toString())} %';

  Widget _kpi(String label, String value, {String? sub, Key? key}) => Card(
    key: key,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        width: 180,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            if (sub != null)
              Text(sub, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    ),
  );

  Widget _section(String title, String table, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            TextButton.icon(
              key: ValueKey('csv-$table'),
              icon: const Icon(AppIcons.copyAll, size: 18),
              label: Text(context.l10n.exportCsv),
              onPressed: () => _csv(table),
            ),
          ],
        ),
      ),
      child,
    ],
  );

  Widget _body(BuildContext context, Report r) {
    final l = context.l10n;
    final basis = switch (r.basis) {
      'business' => l.basisBusiness,
      'mixed' => l.basisMixed,
      _ => l.basisElapsed,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Wrap(
          children: [
            _kpi(
              l.slaCompliance,
              _percent(r.sla.compliancePercent),
              sub: l.slaComplianceDetail(r.sla.breached, r.sla.tickets),
              key: const ValueKey('kpi-sla'),
            ),
            _kpi(
              l.firstResponseTime,
              _minutes(r.firstResponse.averageMinutes),
              sub: '${l.p90}: ${_minutes(r.firstResponse.p90Minutes)} · $basis',
              key: const ValueKey('kpi-first'),
            ),
            _kpi(
              l.resolutionTime,
              _minutes(r.resolution.averageMinutes),
              sub: '${l.p90}: ${_minutes(r.resolution.p90Minutes)} · $basis',
              key: const ValueKey('kpi-resolution'),
            ),
            _kpi(
              l.csatAverage,
              _percent(r.csat.averagePercent),
              sub: l.csatResponses(r.csat.responses),
              key: const ValueKey('kpi-csat'),
            ),
          ],
        ),
        _section(
          l.ticketVolume,
          'volume',
          VolumeChart(
            points: r.volume,
            createdLabel: l.created,
            closedLabel: l.closedLabel,
          ),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 900;
            final cards = [
              _section(
                l.backlogByStatus,
                'backlog_status',
                BarList(
                  rows: [
                    for (final x in r.backlogByStatus)
                      CountRow(
                        key: x.key,
                        label: l.ticketStatus(x.key),
                        count: x.count,
                      ),
                  ],
                ),
              ),
              _section(
                l.backlogByPriority,
                'backlog_priority',
                BarList(
                  rows: [
                    for (final x in r.backlogByPriority)
                      CountRow(
                        key: x.key,
                        label: l.ticketPriority(x.key),
                        count: x.count,
                      ),
                  ],
                ),
              ),
              _section(
                l.backlogByTeam,
                'backlog_team',
                BarList(rows: r.backlogByTeam),
              ),
              _section(
                l.backlogByOwner,
                'backlog_owner',
                BarList(rows: r.backlogByOwner),
              ),
            ];
            return wide
                ? Wrap(
                    spacing: 32,
                    children: [
                      for (final c in cards) SizedBox(width: 420, child: c),
                    ],
                  )
                : Column(children: cards);
          },
        ),
        _section(
          l.breachesByTeam,
          'breaches_by_team',
          r.breachesByTeam.isEmpty
              ? const Text('—')
              : Table(
                  columnWidths: const {
                    0: FlexColumnWidth(3),
                    1: FlexColumnWidth(),
                    2: FlexColumnWidth(),
                  },
                  children: [
                    TableRow(
                      children: [
                        Text(l.team),
                        Text(l.tickets, textAlign: TextAlign.end),
                        Text(l.breached, textAlign: TextAlign.end),
                      ],
                    ),
                    for (final t in r.breachesByTeam)
                      TableRow(
                        children: [
                          Text(t.team.isEmpty ? '—' : t.team),
                          Text('${t.tickets}', textAlign: TextAlign.end),
                          Text('${t.breached}', textAlign: TextAlign.end),
                        ],
                      ),
                  ],
                ),
        ),
        _section(
          l.topCategories,
          'top_categories',
          BarList(
            rows: [
              for (final x in r.topCategories)
                CountRow(
                  key: x.key,
                  label: l.ticketCategory(x.key),
                  count: x.count,
                ),
            ],
          ),
        ),
        _section(l.topTags, 'top_tags', BarList(rows: r.topTags)),
        _section(
          l.timeLogged,
          'time_by_user',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.billable}: ${minutesText(r.timeBillableMinutes)} · '
                '${l.nonBillable}: ${minutesText(r.timeNonBillableMinutes)}',
              ),
              for (final t in r.timeByUser)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.name),
                  trailing: Text(
                    '${minutesText(t.totalMinutes)} '
                    '(${l.billable} ${minutesText(t.billableMinutes)})',
                  ),
                ),
            ],
          ),
        ),
        _section(
          l.slaAndSatisfaction,
          'sla',
          Text(
            '${l.slaCompliance}: ${_percent(r.sla.compliancePercent)} · '
            '${l.csatAverage}: ${_percent(r.csat.averagePercent)}',
          ),
        ),
        _section(
          l.responseTimes,
          'times',
          Text(
            '${l.firstResponseTime}: ${_minutes(r.firstResponse.averageMinutes)} · '
            '${l.resolutionTime}: ${_minutes(r.resolution.averageMinutes)} ($basis)',
          ),
        ),
      ],
    );
  }
}
