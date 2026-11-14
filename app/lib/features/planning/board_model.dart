import 'package:material_ui/material_ui.dart';

/// The time axis of one day cell: which minutes of the day are visible and how wide a minute is.
/// Generic on purpose: a work-centre board can use the same axis for machines instead of people.
class BoardAxis {
  const BoardAxis({
    required this.startMinute,
    required this.endMinute,
    required this.pxPerMinute,
    this.snapMinutes = 15,
  });

  final int startMinute;
  final int endMinute;
  final double pxPerMinute;
  final int snapMinutes;

  int get minutes => endMinute - startMinute;
  double get width => minutes * pxPerMinute;

  /// Horizontal position of a minute of the day, clamped to the axis.
  double xOf(int minuteOfDay) =>
      (minuteOfDay.clamp(startMinute, endMinute) - startMinute) * pxPerMinute;

  /// The minute of the day at a horizontal position, snapped to [snapMinutes].
  int minuteAt(double dx) {
    final raw = startMinute + dx / pxPerMinute;
    final snapped = (raw / snapMinutes).round() * snapMinutes;
    return snapped.clamp(0, 24 * 60);
  }

  BoardAxis withPxPerMinute(double px) => BoardAxis(
    startMinute: startMinute,
    endMinute: endMinute,
    pxPerMinute: px,
    snapMinutes: snapMinutes,
  );
}

enum ShadeKind { offHours, absence }

/// A shaded part of one day of one row: outside working hours, or an absence.
class BoardShade {
  const BoardShade({
    required this.day,
    required this.startMinute,
    required this.endMinute,
    required this.kind,
    this.label,
  });

  final DateTime day;
  final int startMinute;
  final int endMinute;
  final ShadeKind kind;
  final String? label;
}

/// A line of the board (a technician; later a work centre).
class BoardRow {
  const BoardRow({
    required this.id,
    required this.title,
    this.subtitle,
    this.shades = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final List<BoardShade> shades;
}

/// A block on the board: something that takes time on a row.
class BoardItem {
  const BoardItem({
    required this.id,
    required this.rowId,
    required this.start,
    required this.end,
    required this.title,
    this.subtitle,
    this.color = Colors.blue,
    this.locked = false,
    this.data,
  });

  final String id;
  final String rowId;
  final DateTime start;
  final DateTime end;
  final String title;
  final String? subtitle;
  final Color color;

  /// A locked block can be opened but not dragged (e.g. a completed job).
  final bool locked;

  /// What the owner of the board attached (e.g. the job).
  final Object? data;
}

/// What is being dragged: from the backlog or from another block.
class BoardDragData {
  const BoardDragData({
    required this.payload,
    required this.duration,
    required this.label,
    required this.color,
    this.fromRowId,
  });

  final Object payload;
  final Duration duration;
  final String label;
  final Color color;

  /// The row the block comes from; empty for a backlog item.
  final String? fromRowId;
}

/// Where a drag would land: a row and a snapped start.
class BoardDrop {
  const BoardDrop({
    required this.data,
    required this.rowId,
    required this.start,
  });

  final BoardDragData data;
  final String rowId;
  final DateTime start;
  DateTime get end => start.add(data.duration);
}

/// The ghost shown while dragging, tinted by the result of the conflict check.
class BoardPreview {
  const BoardPreview({
    required this.rowId,
    required this.start,
    required this.end,
    this.color,
  });

  final String rowId;
  final DateTime start;
  final DateTime end;
  final Color? color;
}

/// Gives overlapping blocks of one row and day their own lane (greedy, by start time).
/// Returns the lane of each interval, in the order given, and the number of lanes.
({List<int> lanes, int count}) assignLanes(List<(DateTime, DateTime)> spans) {
  final order = List<int>.generate(spans.length, (i) => i)
    ..sort((a, b) => spans[a].$1.compareTo(spans[b].$1));
  final laneEnds = <DateTime>[];
  final lanes = List<int>.filled(spans.length, 0);
  for (final i in order) {
    var lane = laneEnds.indexWhere((e) => !e.isAfter(spans[i].$1));
    if (lane < 0) {
      lane = laneEnds.length;
      laneEnds.add(spans[i].$2);
    } else {
      laneEnds[lane] = spans[i].$2;
    }
    lanes[i] = lane;
  }
  return (lanes: lanes, count: laneEnds.isEmpty ? 1 : laneEnds.length);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
