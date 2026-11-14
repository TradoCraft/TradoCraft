import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'board_model.dart';

/// Minutes since midnight of "HH:mm" or "HH:mm:ss".
int minutesOfText(String t) {
  final p = t.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String twoDigits(int n) => n.toString().padLeft(2, '0');

String clockText(int minutes) =>
    '${twoDigits(minutes ~/ 60)}:${twoDigits(minutes % 60)}';

/// The visible part of each day: working hours and jobs of the period, at least 07:00-19:00.
(int, int) axisRange(Board b) {
  var start = 7 * 60, end = 19 * 60;
  for (final t in b.technicians) {
    for (final h in t.workingHours) {
      final s = minutesOfText(h.startTime), e = minutesOfText(h.endTime);
      if (s < start) start = s;
      if (e > end) end = e;
    }
  }
  for (final j in [...b.jobs]) {
    final s = j.scheduledStart?.toLocal(), e = j.scheduledEnd?.toLocal();
    if (s != null && s.hour * 60 + s.minute < start) {
      start = s.hour * 60 + s.minute;
    }
    if (e != null && e.day == s?.day && e.hour * 60 + e.minute > end) {
      end = e.hour * 60 + e.minute;
    }
  }
  start = (start ~/ 60) * 60;
  end = ((end + 59) ~/ 60) * 60;
  return (start.clamp(0, 22 * 60), end.clamp(start + 120, 24 * 60));
}

Color priorityColor(String priority, {bool done = false}) {
  if (done) return Colors.blueGrey.shade300;
  return switch (priority) {
    'urgent' => Colors.red.shade700,
    'high' => Colors.orange.shade800,
    'low' => Colors.blueGrey.shade500,
    _ => Colors.blue.shade700,
  };
}

/// Technicians (those with [skillId], when given) as rows, with shading for time outside their
/// working hours and for absences.
List<BoardRow> boardRows(
  Board b,
  List<DateTime> days,
  AppLocalizations l, {
  String? skillId,
}) {
  return [
    for (final t in b.technicians)
      if (skillId == null || t.skills.any((s) => s.skillId == skillId))
        BoardRow(
          id: t.userId,
          title: t.displayName,
          subtitle: t.skills.map((s) => s.code).join(' · '),
          shades: [for (final d in days) ..._shades(t, d, l)],
        ),
  ];
}

List<BoardShade> _shades(BoardTechnician t, DateTime day, AppLocalizations l) {
  for (final a in t.absences) {
    if (!dateOnly(a.fromDate).isAfter(day) &&
        !dateOnly(a.toDate).isBefore(day)) {
      return [
        BoardShade(
          day: day,
          startMinute: 0,
          endMinute: 24 * 60,
          kind: ShadeKind.absence,
          label: l.planningAbsenceKind(a.kind),
        ),
      ];
    }
  }
  if (t.workingHours.isEmpty) {
    return const []; // no hours defined: nothing to shade
  }
  final slots = [
    for (final h in t.workingHours)
      if (h.weekday == day.weekday)
        (minutesOfText(h.startTime), minutesOfText(h.endTime)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <BoardShade>[];
  var cursor = 0;
  for (final (s, e) in slots) {
    if (s > cursor) {
      out.add(
        BoardShade(
          day: day,
          startMinute: cursor,
          endMinute: s,
          kind: ShadeKind.offHours,
        ),
      );
    }
    if (e > cursor) cursor = e;
  }
  if (cursor < 24 * 60) {
    out.add(
      BoardShade(
        day: day,
        startMinute: cursor,
        endMinute: 24 * 60,
        kind: ShadeKind.offHours,
      ),
    );
  }
  return out;
}

/// One block per assigned technician (of the rows that are shown).
List<BoardItem> boardItems(Board b, Set<String> rowIds) {
  final out = <BoardItem>[];
  for (final j in b.jobs) {
    final s = j.scheduledStart?.toLocal();
    if (s == null) continue;
    final e =
        j.scheduledEnd?.toLocal() ??
        s.add(Duration(minutes: b.settings.defaultJobMinutes));
    final done = j.status == 'completed';
    for (final t in j.technicianIds) {
      if (!rowIds.contains(t)) continue;
      out.add(
        BoardItem(
          id: '${j.id}:$t',
          rowId: t,
          start: s,
          end: e,
          title: '${j.number} ${j.title}',
          subtitle: [j.customerName, if (j.city.isNotEmpty) j.city].join(' · '),
          color: priorityColor(j.priority, done: done),
          locked: done,
          data: j,
        ),
      );
    }
  }
  return out;
}

/// How long a job takes on the board: its appointment, else the company's default.
Duration jobDuration(BoardJob j, Board b) {
  final s = j.scheduledStart, e = j.scheduledEnd;
  if (s != null && e != null && e.isAfter(s)) return e.difference(s);
  return Duration(minutes: b.settings.defaultJobMinutes);
}

/// The technicians of a job after dropping it on [target]: a block moved from a row replaces that
/// technician; a backlog job goes to the target alone.
List<String> techniciansAfterDrop(BoardJob job, String? from, String target) {
  if (from == null) return [target];
  final out = [
    for (final t in job.technicianIds)
      if (t != from) t,
    target,
  ];
  return out.toSet().toList();
}

/// The text for a conflict, naming the technician and skill.
String conflictText(
  AppLocalizations l,
  Conflict c,
  Map<String, String> technicianNames,
  Map<String, String> skillNames,
) {
  final who = technicianNames[c.technicianId] ?? '';
  return switch (c.kind) {
    ConflictKind.doubleBooked => l.planningConflictDoubleBooked(who),
    ConflictKind.outsideHours => l.planningConflictOutsideHours(who),
    ConflictKind.onAbsence => l.planningConflictOnAbsence(who),
    ConflictKind.missingSkill => l.planningConflictMissingSkill(
      who,
      skillNames[c.skillId] ?? '',
    ),
    ConflictKind.crossesDays => l.planningConflictCrossesDays,
    _ => c.messageKey,
  };
}

bool hasErrors(List<Conflict> c) => c.any((x) => x.severity == Severity.error);

extension PlanningLabels on AppLocalizations {
  String planningAbsenceKind(String kind) => switch (kind) {
    'vacation' => planningAbsenceVacation,
    'sick' => planningAbsenceSick,
    'training' => planningAbsenceTraining,
    _ => planningAbsenceOther,
  };
}
