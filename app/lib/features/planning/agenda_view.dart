import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'backlog_panel.dart';
import 'board_model.dart';
import 'planning_adapter.dart';
import '../../shared/app_icons.dart';

final _time = DateFormat('HH:mm');

/// The phone layout: one day as a list per technician (no dragging), and the backlog below.
class AgendaView extends StatelessWidget {
  const AgendaView({
    super.key,
    required this.board,
    required this.day,
    required this.skillId,
    required this.onOpen,
    required this.onPlan,
  });

  final Board board;
  final DateTime day;
  final String? skillId;
  final void Function(BoardJob job) onOpen;
  final void Function(BoardJob job) onPlan;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final techs = [
      for (final t in board.technicians)
        if (skillId == null || t.skills.any((s) => s.skillId == skillId)) t,
    ];
    final next = day.add(const Duration(days: 1));
    return ListView(
      key: const ValueKey('planning-agenda'),
      padding: const EdgeInsets.all(12),
      children: [
        if (techs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l.planningNoTechnicians),
          ),
        for (final t in techs)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.displayName, style: theme.textTheme.titleMedium),
                  ..._absence(context, t),
                  ..._jobs(context, t, next),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        BacklogPanel(
          board: board,
          jobs: [
            for (final j in board.backlog)
              if (skillId == null || j.requiredSkillIds.contains(skillId)) j,
          ],
          pxPerMinute: 1,
          draggable: false,
          onPlan: onPlan,
          onOpen: onOpen,
        ),
      ],
    );
  }

  List<Widget> _absence(BuildContext context, BoardTechnician t) {
    final l = context.l10n;
    for (final a in t.absences) {
      if (!dateOnly(a.fromDate).isAfter(day) &&
          !dateOnly(a.toDate).isBefore(day)) {
        return [
          Chip(
            key: ValueKey('absence-${t.userId}'),
            avatar: const Icon(AppIcons.beachAccess, size: 16),
            label: Text(l.planningAbsenceKind(a.kind)),
          ),
        ];
      }
    }
    return const [];
  }

  List<Widget> _jobs(BuildContext context, BoardTechnician t, DateTime next) {
    final l = context.l10n;
    final mine = [
      for (final j in board.jobs)
        if (j.technicianIds.contains(t.userId) &&
            j.scheduledStart != null &&
            j.scheduledStart!.toLocal().isBefore(next) &&
            (j.scheduledEnd ?? j.scheduledStart!).toLocal().isAfter(day))
          j,
    ]..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
    if (mine.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(l.planningAgendaEmpty),
        ),
      ];
    }
    return [
      for (final j in mine)
        ListTile(
          key: ValueKey('agenda-${j.id}'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          onTap: () => onOpen(j),
          leading: Text(
            '${_time.format(j.scheduledStart!.toLocal())}\n${j.scheduledEnd == null ? '' : _time.format(j.scheduledEnd!.toLocal())}',
            textAlign: TextAlign.center,
          ),
          title: Text('${j.number} · ${j.title}'),
          subtitle: Text(
            [j.customerName, if (j.city.isNotEmpty) j.city].join(' · '),
          ),
          trailing: j.status == 'completed'
              ? const Icon(AppIcons.checkCircle)
              : IconButton(
                  tooltip: l.planningScheduleJob(j.number),
                  icon: const Icon(AppIcons.editCalendar),
                  onPressed: () => onPlan(j),
                ),
        ),
    ];
  }
}
