import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart' as fmt;

/// One value of a report as text, by the type of its column.
String reportCell(BuildContext context, ReportFieldType type, dynamic v) {
  if (v == null) return '';
  switch (type) {
    case ReportFieldType.number:
      return fmt.number(v.toString());
    case ReportFieldType.date:
      final d = DateTime.tryParse(v.toString());
      return d == null ? v.toString() : fmt.date(d);
    case ReportFieldType.datetime:
      final d = DateTime.tryParse(v.toString())?.toLocal();
      if (d == null) return v.toString();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${fmt.date(d)} ${two(d.hour)}:${two(d.minute)}';
    case ReportFieldType.valueBool:
      return v == true ? context.l10n.yes : context.l10n.no;
    default:
      return v.toString();
  }
}

/// The result of a report: the chart (when the report has one), the rows and, for grouped
/// reports, a totals line. [onLoadMore] shows a button while there are rows left to fetch.
class ReportResultView extends StatelessWidget {
  const ReportResultView({
    super.key,
    required this.result,
    this.onLoadMore,
    this.loadingMore = false,
  });

  final ReportRunResult result;
  final VoidCallback? onLoadMore;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final more = result.rows.length < result.total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (result.chart != null && result.rows.isNotEmpty) ...[
          ReportChartView(result: result),
          const SizedBox(height: 16),
        ],
        Text(
          // Without a "show more" button, say how many of the rows are on screen.
          more && onLoadMore == null
              ? l.crRowsShown(result.rows.length, result.total)
              : l.crRows(result.total),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        if (result.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(l.crNoRows),
          )
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 24,
              headingRowHeight: 40,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 40,
              columns: [
                for (final c in result.columns)
                  DataColumn(
                    label: Text(
                      c.label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    numeric: c.type == ReportFieldType.number,
                  ),
              ],
              rows: [
                for (final row in result.rows)
                  DataRow(
                    cells: [
                      for (var i = 0; i < result.columns.length; i++)
                        DataCell(
                          Text(
                            reportCell(context, result.columns[i].type, row[i]),
                          ),
                        ),
                    ],
                  ),
                if (result.totals != null && !more)
                  DataRow(
                    cells: [
                      for (var i = 0; i < result.columns.length; i++)
                        DataCell(
                          Text(
                            i == 0 && result.totals![i] == null
                                ? l.total
                                : reportCell(
                                    context,
                                    result.columns[i].type,
                                    result.totals![i],
                                  ),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        if (more && onLoadMore != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: loadingMore
                ? const Center(child: CircularProgressIndicator())
                : TextButton(onPressed: onLoadMore, child: Text(l.crLoadMore)),
          ),
      ],
    );
  }
}

/// A chart of a grouped report: bars (also used for pie, with the share of the total) or a line.
class ReportChartView extends StatelessWidget {
  const ReportChartView({super.key, required this.result});

  final ReportRunResult result;

  static const maxPoints = 30;

  @override
  Widget build(BuildContext context) {
    final chart = result.chart;
    if (chart == null) return const SizedBox.shrink();
    final xi = result.columns.indexWhere((c) => c.key == chart.x);
    final yi = result.columns.indexWhere((c) => c.key == chart.y);
    if (xi < 0 || yi < 0) return const SizedBox.shrink();
    final labels = <String>[];
    final values = <double>[];
    final texts = <String>[];
    for (final row in result.rows.take(maxPoints)) {
      labels.add(reportCell(context, result.columns[xi].type, row[xi]));
      final v = row[yi];
      values.add(v is num ? v.toDouble() : 0);
      texts.add(reportCell(context, result.columns[yi].type, v));
    }
    final pie = chart.kind == ReportChartKind.pie;
    // A pie's shares are of the groups drawn, so say so when some groups are left out.
    final partial =
        pie && result.rows.length > labels.length ||
        pie && result.rows.length < result.total;
    final title = '${result.columns[yi].label} / ${result.columns[xi].label}';
    final color = Theme.of(context).colorScheme.primary;
    final style = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: style.titleSmall),
        const SizedBox(height: 8),
        if (chart.kind == ReportChartKind.line)
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _LinePainter(
                values: values,
                firstLabel: labels.first,
                lastLabel: labels.last,
                color: color,
                textColor: style.bodySmall?.color ?? Colors.black54,
              ),
            ),
          )
        else
          _Bars(
            labels: labels,
            values: values,
            texts: texts,
            color: color,
            pie: pie,
          ),
        if (partial)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.l10n.crChartShareShown(labels.length),
              style: style.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({
    required this.labels,
    required this.values,
    required this.texts,
    required this.color,
    required this.pie,
  });

  final List<String> labels;
  final List<double> values;
  final List<String> texts;
  final Color color;
  final bool pie;

  @override
  Widget build(BuildContext context) {
    final positive = values.map((v) => v < 0 ? 0.0 : v).toList();
    final max = positive.fold<double>(0, (m, v) => v > m ? v : m);
    final sum = positive.fold<double>(0, (s, v) => s + v);
    return Column(
      children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                SizedBox(
                  width: 160,
                  child: Text(
                    labels[i].isEmpty ? '—' : labels[i],
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: max > 0 ? positive[i] / max : 0,
                      child: Container(height: 12, color: color),
                    ),
                  ),
                ),
                SizedBox(
                  width: pie ? 130 : 90,
                  child: Text(
                    pie && sum > 0
                        ? '${texts[i]} (${(positive[i] / sum * 100).toStringAsFixed(1).replaceAll('.', ',')} %)'
                        : texts[i],
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.values,
    required this.firstLabel,
    required this.lastLabel,
    required this.color,
    required this.textColor,
  });

  final List<double> values;
  final String firstLabel;
  final String lastLabel;
  final Color color;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 20.0;
    final w = size.width - 2 * pad;
    final h = size.height - 2 * pad;
    final base = Paint()
      ..color = textColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(pad, size.height - pad),
      Offset(size.width - pad, size.height - pad),
      base,
    );
    if (values.isEmpty) return;
    final lo = values.fold<double>(0, (m, v) => v < m ? v : m);
    final hi = values.fold<double>(0, (m, v) => v > m ? v : m);
    final span = hi - lo == 0 ? 1.0 : hi - lo;
    Offset point(int i) => Offset(
      pad + (values.length == 1 ? w / 2 : w * i / (values.length - 1)),
      pad + h - h * (values[i] - lo) / span,
    );
    final line = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(point(i).dx, point(i).dy);
    }
    canvas.drawPath(path, line);
    final dot = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(point(i), 3, dot);
    }
    void label(String text, double x, {required bool right}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: 11, color: textColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width / 2);
      tp.paint(canvas, Offset(right ? x - tp.width : x, size.height - pad + 3));
    }

    label(firstLabel, pad, right: false);
    if (values.length > 1) label(lastLabel, size.width - pad, right: true);
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.values != values ||
      old.firstLabel != firstLabel ||
      old.lastLabel != lastLabel ||
      old.color != color;
}
