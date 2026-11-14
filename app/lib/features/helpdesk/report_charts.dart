import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';

/// Tickets created and closed per day or week as grouped bars (no charting package).
class VolumeChart extends StatelessWidget {
  const VolumeChart({
    super.key,
    required this.points,
    this.createdLabel = 'created',
    this.closedLabel = 'closed',
    this.height = 180,
  });

  final List<VolumePoint> points;
  final String createdLabel;
  final String closedLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelSmall!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Legend(color: scheme.primary, label: createdLabel),
            const SizedBox(width: 16),
            _Legend(color: scheme.tertiary, label: closedLabel),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            key: const ValueKey('volume-chart'),
            painter: VolumePainter(
              created: [for (final p in points) p.created],
              closed: [for (final p in points) p.closed],
              labels: [
                for (final p in points)
                  '${p.period.day.toString().padLeft(2, '0')}/${p.period.month.toString().padLeft(2, '0')}',
              ],
              createdColor: scheme.primary,
              closedColor: scheme.tertiary,
              axisColor: scheme.outlineVariant,
              textStyle: style.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 4),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

/// Draws the bars: the largest value fills the height, labels show for a readable subset.
class VolumePainter extends CustomPainter {
  VolumePainter({
    required this.created,
    required this.closed,
    required this.labels,
    required this.createdColor,
    required this.closedColor,
    required this.axisColor,
    required this.textStyle,
  });

  final List<int> created;
  final List<int> closed;
  final List<String> labels;
  final Color createdColor, closedColor, axisColor;
  final TextStyle textStyle;

  /// Height of a bar for [value] when the tallest is [max] and the plot is [plot] high.
  static double barHeight(int value, int max, double plot) =>
      max <= 0 ? 0 : plot * value / max;

  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0, top = 14.0;
    final plot = size.height - bottom - top;
    final n = created.length;
    if (n == 0 || plot <= 0) return;
    final max = [...created, ...closed].fold<int>(0, (m, v) => v > m ? v : m);
    final axis = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, top + plot),
      Offset(size.width, top + plot),
      axis,
    );
    final slot = size.width / n;
    final bar = (slot * 0.38).clamp(1.0, 22.0);
    final every = (n / 12).ceil().clamp(1, n);
    for (var i = 0; i < n; i++) {
      final x = slot * i + slot / 2;
      for (final (k, v, color) in [
        (-1, created[i], createdColor),
        (0, closed[i], closedColor),
      ]) {
        final h = barHeight(v, max, plot);
        if (h > 0) {
          canvas.drawRect(
            Rect.fromLTWH(x + k * bar, top + plot - h, bar, h),
            Paint()..color = color,
          );
        }
      }
      if (i % every == 0) {
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, top + plot + 3));
      }
    }
    final tp = TextPainter(
      text: TextSpan(text: '$max', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(0, 0));
  }

  @override
  bool shouldRepaint(VolumePainter old) =>
      old.created != created || old.closed != closed || old.labels != labels;
}

/// A list of labelled horizontal bars with the count at the end.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.rows, this.emptyLabel = '—'});

  final List<CountRow> rows;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return Text(emptyLabel);
    final max = rows.fold<int>(1, (m, r) => r.count > m ? r.count : m);
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  child: Text(
                    r.label.isEmpty ? '—' : r.label,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: r.count / max,
                      child: Container(height: 12, color: color),
                    ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text('${r.count}', textAlign: TextAlign.end),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
