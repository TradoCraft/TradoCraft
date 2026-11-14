import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'board_model.dart';
import 'planning_adapter.dart';
import 'resource_board.dart';

/// The jobs that still have to be planned. On a wide screen each card can be dragged onto the
/// board; every card also has a Plan button that opens the schedule dialog.
class BacklogPanel extends StatelessWidget {
  const BacklogPanel({
    super.key,
    required this.board,
    required this.jobs,
    required this.pxPerMinute,
    required this.onPlan,
    required this.onOpen,
    this.draggable = true,
  });

  final Board board;
  final List<BoardJob> jobs;
  final double pxPerMinute;
  final void Function(BoardJob job) onPlan;
  final void Function(BoardJob job) onOpen;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final skillNames = {for (final s in board.skills) s.id: s.name};
    return Column(
      mainAxisSize: draggable ? MainAxisSize.max : MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Text(
            '${l.planningBacklog} (${jobs.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (jobs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(l.planningBacklogEmpty),
          ),
        if (draggable)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [for (final j in jobs) _card(context, j, skillNames)],
            ),
          )
        else
          // Inside the phone agenda, which scrolls itself.
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [for (final j in jobs) _card(context, j, skillNames)],
            ),
          ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    BoardJob j,
    Map<String, String> skillNames,
  ) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final card = Card(
      key: ValueKey('backlog-${j.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => onOpen(j),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(width: 4, height: 48, color: priorityColor(j.priority)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${j.number} · ${j.title}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      [
                        j.customerName,
                        if (j.city.isNotEmpty) j.city,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    Wrap(
                      spacing: 4,
                      children: [
                        Text(
                          l.ticketPriority(j.priority),
                          style: theme.textTheme.labelSmall,
                        ),
                        for (final s in j.requiredSkillIds)
                          Chip(
                            label: Text(skillNames[s] ?? '?'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelStyle: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => onPlan(j),
                child: Text(l.planningPlan),
              ),
            ],
          ),
        ),
      ),
    );
    if (!draggable) return card;
    return BoardDraggable(
      data: BoardDragData(
        payload: j,
        duration: jobDuration(j, board),
        label: '${j.number} ${j.title}',
        color: priorityColor(j.priority),
      ),
      pxPerMinute: pxPerMinute,
      child: card,
    );
  }
}
