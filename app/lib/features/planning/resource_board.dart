import 'package:material_ui/material_ui.dart';

import 'board_model.dart';

const double boardLabelWidth = 148;
const double boardHeaderHeight = 40;
const double boardLaneHeight = 46;

/// A grid of rows (resources) by days, with blocks positioned by time and a drop target in every
/// cell. It knows nothing about jobs: the owner supplies rows, items and what a drop means.
class ResourceBoard extends StatefulWidget {
  const ResourceBoard({
    super.key,
    required this.days,
    required this.rows,
    required this.items,
    required this.axis,
    required this.dayHeader,
    required this.onDrop,
    this.onTapItem,
    this.onPreview,
    this.onPreviewEnd,
    this.preview,
    this.rowTrailing,
  });

  final List<DateTime> days;
  final List<BoardRow> rows;
  final List<BoardItem> items;
  final BoardAxis axis;
  final String Function(DateTime day) dayHeader;
  final void Function(BoardDrop drop) onDrop;
  final void Function(BoardItem item)? onTapItem;

  /// Called (snapped, only when it changes) while a drag hovers a cell.
  final void Function(BoardDrop drop)? onPreview;
  final VoidCallback? onPreviewEnd;
  final BoardPreview? preview;
  final Widget Function(BoardRow row)? rowTrailing;

  @override
  State<ResourceBoard> createState() => _ResourceBoardState();
}

class _ResourceBoardState extends State<ResourceBoard> {
  String? _lastPreview;

  double get _dayWidth => widget.axis.width;

  /// Items of a row, cut to the days they touch.
  Map<String, List<_Segment>> _segments() {
    final out = <String, List<_Segment>>{};
    for (final it in widget.items) {
      for (final day in widget.days) {
        final from = day, to = day.add(const Duration(days: 1));
        final s = it.start.isAfter(from) ? it.start : from;
        final e = it.end.isBefore(to) ? it.end : to;
        if (!e.isAfter(s) &&
            !(it.start == it.end &&
                !it.start.isBefore(from) &&
                it.start.isBefore(to))) {
          continue;
        }
        (out['${it.rowId}|${dayKey(day)}'] ??= []).add(
          _Segment(it, s, e, from),
        );
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final segs = _segments();
    // A row is as high as its busiest day.
    final lanes = <String, ({List<int> lanes, int count})>{};
    final heights = <String, double>{};
    for (final r in widget.rows) {
      var most = 1;
      for (final d in widget.days) {
        final list = segs['${r.id}|${dayKey(d)}'] ?? const <_Segment>[];
        final l = assignLanes([for (final s in list) (s.start, s.end)]);
        lanes['${r.id}|${dayKey(d)}'] = l;
        if (l.count > most) most = l.count;
      }
      heights[r.id] = most * boardLaneHeight + 6;
    }
    final theme = Theme.of(context);

    final labels = Column(
      children: [
        SizedBox(height: boardHeaderHeight, width: boardLabelWidth),
        for (final r in widget.rows)
          Container(
            width: boardLabelWidth,
            height: heights[r.id],
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (r.subtitle != null)
                        Text(
                          r.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                ),
                if (widget.rowTrailing != null) widget.rowTrailing!(r),
              ],
            ),
          ),
      ],
    );

    final grid = Column(
      children: [
        SizedBox(
          height: boardHeaderHeight,
          child: Row(
            children: [
              for (final d in widget.days)
                Container(
                  width: _dayWidth,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border(left: BorderSide(color: theme.dividerColor)),
                  ),
                  child: Text(
                    widget.dayHeader(d),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
            ],
          ),
        ),
        for (final r in widget.rows)
          SizedBox(
            height: heights[r.id],
            child: Row(
              children: [
                for (final d in widget.days)
                  _Cell(
                    key: ValueKey('cell-${r.id}-${dayKey(d)}'),
                    row: r,
                    day: d,
                    axis: widget.axis,
                    segments: segs['${r.id}|${dayKey(d)}'] ?? const [],
                    lanes: lanes['${r.id}|${dayKey(d)}']!.lanes,
                    preview: widget.preview?.rowId == r.id
                        ? widget.preview
                        : null,
                    onTapItem: widget.onTapItem,
                    onDrop: widget.onDrop,
                    onMove: _move,
                    onLeave: _leave,
                    onDragEnd: _leave,
                  ),
              ],
            ),
          ),
      ],
    );

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          labels,
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: grid,
            ),
          ),
        ],
      ),
    );
  }

  void _move(BoardDrop drop) {
    final key = '${drop.rowId}|${drop.start.toIso8601String()}';
    if (key == _lastPreview) return;
    _lastPreview = key;
    widget.onPreview?.call(drop);
  }

  void _leave() {
    _lastPreview = null;
    widget.onPreviewEnd?.call();
  }
}

class _Segment {
  const _Segment(this.item, this.start, this.end, this.dayStart);
  final BoardItem item;
  final DateTime start;
  final DateTime end;
  final DateTime dayStart;
}

class _Cell extends StatelessWidget {
  const _Cell({
    super.key,
    required this.row,
    required this.day,
    required this.axis,
    required this.segments,
    required this.lanes,
    required this.preview,
    required this.onTapItem,
    required this.onDrop,
    required this.onMove,
    required this.onLeave,
    required this.onDragEnd,
  });

  final BoardRow row;
  final DateTime day;
  final BoardAxis axis;
  final List<_Segment> segments;
  final List<int> lanes;
  final BoardPreview? preview;
  final void Function(BoardItem)? onTapItem;
  final void Function(BoardDrop) onDrop;
  final void Function(BoardDrop) onMove;
  final VoidCallback onLeave;
  final VoidCallback onDragEnd;

  BoardDrop? _drop(BuildContext context, DragTargetDetails<BoardDragData> d) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(d.offset);
    final minute = axis.minuteAt(local.dx);
    return BoardDrop(
      data: d.data,
      rowId: row.id,
      start: day.add(Duration(minutes: minute)),
    );
  }

  double _x(DateTime t) {
    final minutes = t.difference(day).inMinutes;
    return axis.xOf(minutes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shades = row.shades.where((s) => dayKey(s.day) == dayKey(day));
    return DragTarget<BoardDragData>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (d) {
        final drop = _drop(context, d);
        if (drop != null) onMove(drop);
      },
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (d) {
        final drop = _drop(context, d);
        onLeave();
        if (drop != null) onDrop(drop);
      },
      builder: (context, candidate, _) => Container(
        width: axis.width,
        decoration: BoxDecoration(
          color: candidate.isNotEmpty
              ? scheme.primary.withValues(alpha: 0.05)
              : null,
          border: Border(
            left: BorderSide(color: theme.dividerColor),
            bottom: BorderSide(color: theme.dividerColor),
          ),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _HourLines(
                  axis,
                  theme.dividerColor.withValues(alpha: 0.4),
                ),
              ),
            ),
            for (final s in shades)
              Positioned(
                left: axis.xOf(s.startMinute),
                width: axis.xOf(s.endMinute) - axis.xOf(s.startMinute),
                top: 0,
                bottom: 0,
                child: Container(
                  key: ValueKey(
                    'shade-${s.kind.name}-${row.id}-${dayKey(day)}',
                  ),
                  color: s.kind == ShadeKind.absence
                      ? scheme.errorContainer.withValues(alpha: 0.7)
                      : scheme.onSurface.withValues(alpha: 0.07),
                  alignment: Alignment.center,
                  child: s.label == null
                      ? null
                      : Text(
                          s.label!,
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
            if (preview != null) ..._ghost(theme),
            for (var i = 0; i < segments.length; i++)
              _block(context, segments[i], lanes[i]),
          ],
        ),
      ),
    );
  }

  List<Widget> _ghost(ThemeData theme) {
    final p = preview!;
    final from = day, to = day.add(const Duration(days: 1));
    final s = p.start.isAfter(from) ? p.start : from;
    final e = p.end.isBefore(to) ? p.end : to;
    if (!e.isAfter(s)) return const [];
    final color = p.color ?? theme.colorScheme.primary;
    return [
      Positioned(
        key: const ValueKey('ghost'),
        left: _x(s),
        width: (_x(e) - _x(s)).clamp(4, double.infinity),
        top: 2,
        bottom: 2,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    ];
  }

  Widget _block(BuildContext context, _Segment seg, int lane) {
    final it = seg.item;
    final left = _x(seg.start);
    final width = (_x(seg.end) - left).clamp(18.0, double.infinity);
    final body = _BlockBody(item: it, width: width);
    final tap = onTapItem == null ? null : () => onTapItem!(it);
    final child = GestureDetector(onTap: tap, child: body);
    return Positioned(
      key: ValueKey('block-${it.id}-${dayKey(day)}'),
      left: left,
      top: 3 + lane * boardLaneHeight,
      width: width,
      height: boardLaneHeight - 4,
      child: it.locked || it.data == null
          ? child
          : BoardDraggable(
              data: BoardDragData(
                payload: it.data!,
                duration: it.end.difference(it.start),
                label: it.title,
                color: it.color,
                fromRowId: row.id,
              ),
              pxPerMinute: axis.pxPerMinute,
              anchorToChild: true,
              onEnd: onDragEnd,
              child: child,
            ),
    );
  }
}

class _BlockBody extends StatelessWidget {
  const _BlockBody({required this.item, required this.width});
  final BoardItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        ThemeData.estimateBrightnessForColor(item.color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: item.locked ? item.color.withValues(alpha: 0.55) : item.color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: DefaultTextStyle(
        style: (theme.textTheme.labelSmall ?? const TextStyle()).copyWith(
          color: fg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (item.subtitle != null)
              Text(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }
}

/// Something to pick up: a block of the board or an item of a backlog. Hold briefly, then drag
/// (so that scrolling by touch still works). The ghost under the pointer is as wide as the
/// duration on the board's scale.
class BoardDraggable extends StatelessWidget {
  const BoardDraggable({
    super.key,
    required this.data,
    required this.pxPerMinute,
    required this.child,
    this.anchorToChild = false,
    this.onEnd,
  });

  final BoardDragData data;
  final double pxPerMinute;
  final Widget child;

  /// True for a block already on the board: the ghost keeps the grab point, so its left edge
  /// (the start) follows the pointer by the same offset. A backlog item starts at the pointer.
  final bool anchorToChild;
  final VoidCallback? onEnd;

  @override
  Widget build(BuildContext context) {
    final width = (data.duration.inMinutes * pxPerMinute).clamp(40.0, 600.0);
    return LongPressDraggable<BoardDragData>(
      data: data,
      delay: const Duration(milliseconds: 150),
      dragAnchorStrategy: anchorToChild
          ? childDragAnchorStrategy
          : pointerDragAnchorStrategy,
      onDragEnd: (_) => onEnd?.call(),
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: width,
          height: boardLaneHeight - 4,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: data.color.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
          ),
          child: Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: child),
      child: child,
    );
  }
}

/// Thin vertical line at every full hour of the axis.
class _HourLines extends CustomPainter {
  _HourLines(this.axis, this.color);
  final BoardAxis axis;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (
      var m = ((axis.startMinute + 59) ~/ 60) * 60;
      m < axis.endMinute;
      m += 60
    ) {
      final x = axis.xOf(m);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_HourLines old) =>
      old.axis.startMinute != axis.startMinute ||
      old.axis.endMinute != axis.endMinute ||
      old.axis.pxPerMinute != axis.pxPerMinute ||
      old.color != color;
}
