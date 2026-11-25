import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../planning/board_model.dart';

/// The visible part of a day on the work-centre board: 06:00 to 18:00. Operations are planned in
/// whole days (ADR 0090), so a block fills the cells of the days it touches.
const workCentreAxisStart = 6 * 60;
const workCentreAxisEnd = 18 * 60;

/// Conflicts that `force` cannot override: the server refuses the move whatever is asked.
const neverForced = {'inactive_work_centre', 'operation_started'};

/// Whether the move may be made after the planner confirms: no conflict is an error that can
/// never be overridden. An empty list is fine too.
bool canForce(List<ProductionMoveConflict> c) =>
    !c.any((x) => neverForced.contains(x.kind));

bool hasMoveErrors(List<ProductionMoveConflict> c) =>
    c.any((x) => x.severity == 'error');

/// One row per work centre; closed days and overloaded days are shaded.
List<BoardRow> workCentreRows(ProductionPlanningBoard b, List<DateTime> days) {
  final keys = {for (final d in days) dayKey(d)};
  return [
    for (final c in b.centres)
      BoardRow(
        id: c.id,
        title: c.code,
        subtitle: c.name,
        shades: [
          for (final d in c.days)
            if (keys.contains(dayKey(d.date)))
              if (d.availableMinutes == 0)
                BoardShade(
                  day: dateOnly(d.date),
                  startMinute: 0,
                  endMinute: 24 * 60,
                  kind: ShadeKind.closure,
                )
              else if (d.overloaded)
                BoardShade(
                  day: dateOnly(d.date),
                  startMinute: 0,
                  endMinute: 24 * 60,
                  kind: ShadeKind.overload,
                ),
        ],
      ),
  ];
}

/// One block per open operation that is not late (late ones are listed beside the board).
List<BoardItem> workCentreItems(
  ProductionPlanningBoard b, {
  bool canMove = true,
}) {
  final rows = {for (final c in b.centres) c.id};
  return [
    for (final o in b.operations)
      if (!o.lateValue && rows.contains(o.workCentreId))
        BoardItem(
          id: o.id,
          rowId: o.workCentreId,
          start: dateOnly(o.plannedStart)
              .add(const Duration(minutes: workCentreAxisStart)),
          end: dateOnly(o.plannedEnd)
              .add(const Duration(minutes: workCentreAxisEnd)),
          title: '${o.orderNumber} · ${o.name}',
          subtitle: '${o.productName} · ${o.plannedMinutes} min',
          color: o.status == 'in_progress' ? Colors.teal : Colors.indigo,
          locked: o.locked || !canMove,
          data: o,
        ),
  ];
}

/// The update that drops [op] on [rowId] with its first day at [day]: the same number of days,
/// the other work centre when the row differs.
ProductionOperationUpdate moveBody(
  ProductionBoardOperation op,
  String rowId,
  DateTime day,
) {
  final start = dateOnly(day);
  final span = dateOnly(op.plannedEnd).difference(dateOnly(op.plannedStart));
  return ProductionOperationUpdate(
    workCentreId: rowId == op.workCentreId ? null : rowId,
    plannedStart: start,
    plannedEnd: DateTime(start.year, start.month, start.day + span.inDays),
  );
}

/// How loaded a work centre is over the period, in percent; null when it offers no time.
int? utilisation(ProductionCapacityCentre c) => c.totalAvailableMinutes == 0
    ? null
    : (c.totalLoadMinutes * 100 / c.totalAvailableMinutes).round();

/// The translated text of a conflict.
String productionConflictText(
  AppLocalizations l,
  ProductionMoveConflict c,
  String locale,
) {
  final day = c.day == null
      ? ''
      : DateFormat('EEE d MMM', locale).format(c.day!);
  return switch (c.kind) {
    'inactive_work_centre' => l.productionConflictInactiveWorkCentre,
    'operation_started' => l.productionConflictOperationStarted,
    'on_closure' => l.productionConflictOnClosure(day),
    'overload' => l.productionConflictOverload(day),
    'before_predecessor' => l.productionConflictBeforePredecessor(day),
    'after_successor' => l.productionConflictAfterSuccessor(day),
    'later_than_ready' => l.productionConflictLaterThanReady(day),
    _ => c.messageKey,
  };
}
