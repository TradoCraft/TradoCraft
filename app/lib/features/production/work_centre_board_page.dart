import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../planning/board_model.dart';
import '../planning/resource_board.dart';
import 'work_centre_board_adapter.dart';

const double _lateWidth = 300;
const double _phoneWidth = 720;
const double _minDayWidth = 120;

/// The planner's board for the work centres (ADR 0090): work centres as rows, days as columns,
/// open operations as blocks to drag onto another centre or day. Every drag is checked against
/// capacity, closures and the order of the operations before it is made.
class WorkCentreBoardPage extends ConsumerStatefulWidget {
  const WorkCentreBoardPage({super.key, this.initialDay});

  /// A day of the week to start on (this week when empty).
  final DateTime? initialDay;

  @override
  ConsumerState<WorkCentreBoardPage> createState() =>
      _WorkCentreBoardPageState();
}

class _WorkCentreBoardPageState extends ConsumerState<WorkCentreBoardPage> {
  late DateTime _monday = _mondayOf(widget.initialDay ?? DateTime.now());
  Future<ProductionPlanningBoard>? _board;

  BoardPreview? _preview;
  List<ProductionMoveConflict>? _previewConflicts;
  Timer? _debounce;
  int _token = 0;

  static DateTime _mondayOf(DateTime d) {
    final day = dateOnly(d);
    return DateTime(day.year, day.month, day.day - (day.weekday - 1));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  List<DateTime> get _days => [
    for (var i = 0; i < 7; i++)
      DateTime(_monday.year, _monday.month, _monday.day + i),
  ];

  Future<ProductionPlanningBoard> _load() => ref
      .read(apiProvider)
      .production
      .productionPlanningBoard(from: _days.first, to: _days.last);

  void _reload() {
    setState(() {
      _board = _load();
    });
  }

  void _shift(int weeks) {
    _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * weeks);
    _reload();
  }

  void _clearPreview() {
    _debounce?.cancel();
    _token++;
    if (_preview != null || _previewConflicts != null) {
      setState(() {
        _preview = null;
        _previewConflicts = null;
      });
    }
  }

  Future<List<ProductionMoveConflict>> _check(
    ProductionBoardOperation op,
    BoardDrop drop,
  ) async {
    final r = await ref
        .read(apiProvider)
        .production
        .moveProductionOperation(
          id: op.productionOrderId,
          operationId: op.id,
          dryRun: true,
          body: moveBody(op, drop.rowId, drop.start),
        );
    return r.conflicts;
  }

  /// While dragging: the ghost at once, the check shortly after the pointer rests.
  void _onPreview(BoardDrop drop) {
    final op = drop.data.payload as ProductionBoardOperation;
    final token = ++_token;
    _debounce?.cancel();
    final days = calendarDays(op.plannedStart, op.plannedEnd);
    final first = dateOnly(drop.start);
    final start = atMinute(first, workCentreAxisStart);
    final end = atMinute(
      DateTime(first.year, first.month, first.day + days),
      workCentreAxisEnd,
    );
    setState(() {
      _preview = BoardPreview(rowId: drop.rowId, start: start, end: end);
      _previewConflicts = null;
    });
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        final c = await _check(op, drop);
        if (!mounted || token != _token) return;
        setState(() {
          _previewConflicts = c;
          _preview = BoardPreview(
            rowId: drop.rowId,
            start: start,
            end: end,
            color: hasMoveErrors(c)
                ? Colors.red
                : (c.isEmpty ? Colors.green : Colors.orange),
          );
        });
      } catch (_) {
        // The check is a courtesy; the move checks again.
      }
    });
  }

  Future<void> _onDrop(BoardDrop drop) async {
    final op = drop.data.payload as ProductionBoardOperation;
    _clearPreview();
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final conflicts = await _check(op, drop);
      if (!mounted) return;
      var force = false;
      if (hasMoveErrors(conflicts)) {
        final ok = await _confirm(l, locale, conflicts);
        if (ok != true || !mounted) return;
        force = true;
      }
      await ref
          .read(apiProvider)
          .production
          .moveProductionOperation(
            id: op.productionOrderId,
            operationId: op.id,
            force: force ? true : null,
            body: moveBody(op, drop.rowId, drop.start),
          );
      messenger?.showSnackBar(SnackBar(content: Text(l.productionBoardMoved)));
      if (mounted) _reload();
    } on DioException catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(_refusal(l, locale, e))));
    }
  }

  /// The text of a failed move: a refused move (409) names its conflicts, anything else is the
  /// server's message.
  String _refusal(AppLocalizations l, String locale, DioException e) {
    final data = e.response?.data;
    if (e.response?.statusCode == 409 &&
        data is Map &&
        data['conflicts'] is List) {
      final report = ProductionOperationMove.fromJson(
        Map<String, Object?>.from(data),
      );
      final errors = report.conflicts.where((c) => c.severity == 'error');
      if (errors.isNotEmpty) {
        return errors
            .map((c) => productionConflictText(l, c, locale))
            .join(' ');
      }
    }
    return errorMessage(e);
  }

  /// Asks before a move with errors; a move the server will refuse whatever is asked only informs.
  Future<bool?> _confirm(
    AppLocalizations l,
    String locale,
    List<ProductionMoveConflict> conflicts,
  ) {
    final forcible = canForce(conflicts);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          forcible
              ? l.productionBoardConfirmTitle
              : l.productionBoardRefusedTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.productionBoardConfirmBody),
            const SizedBox(height: 8),
            for (final c in conflicts)
              Text('• ${productionConflictText(l, c, locale)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(forcible ? l.cancel : l.close),
          ),
          if (forcible)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.productionBoardMoveAnyway),
            ),
        ],
      ),
    );
  }

  Future<void> _open(ProductionBoardOperation op) async {
    await context.push('/production/${op.productionOrderId}');
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final phone = MediaQuery.sizeOf(context).width < _phoneWidth;
    _board ??= _load();
    return Scaffold(
      appBar: AppBar(title: Text(l.productionBoardTitle)),
      body: !perms.contains('production.read')
          ? const SizedBox.shrink()
          : Column(
              children: [
                // Outside the future: the week can be changed while a week is loading.
                _toolbar(context),
                _banner(context),
                Expanded(
                  child: FutureBuilder<ProductionPlanningBoard>(
                    future: _board,
                    builder: (context, s) {
                      if (s.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(errorMessage(s.error!)),
                              TextButton(
                                onPressed: _reload,
                                child: Text(l.retry),
                              ),
                            ],
                          ),
                        );
                      }
                      // A builder keeps the last answer while the next one is on its way; it
                      // belongs to another week, so wait for this one.
                      if (s.connectionState != ConnectionState.done ||
                          !s.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final b = s.data!;
                      return b.centres.isEmpty
                          ? Center(child: Text(l.productionCapacityEmpty))
                          : phone
                          ? _agenda(b)
                          : _wide(b, perms.contains('production.write'));
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final l = context.l10n;
    final fmt = DateFormat('d MMM', Localizations.localeOf(context).toString());
    final days = _days;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('wc-prev'),
            tooltip: l.planningPrevious,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _shift(-1),
          ),
          OutlinedButton(
            key: const ValueKey('wc-today'),
            onPressed: () {
              _monday = _mondayOf(DateTime.now());
              _reload();
            },
            child: Text(l.planningToday),
          ),
          IconButton(
            key: const ValueKey('wc-next'),
            tooltip: l.planningNext,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _shift(1),
          ),
          Text(
            '${fmt.format(days.first)} – ${fmt.format(days.last)}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }

  /// The conflicts of the placement under the pointer while dragging.
  Widget _banner(BuildContext context) {
    final c = _previewConflicts;
    final Widget content;
    if (_preview == null) {
      content = const SizedBox.shrink();
    } else {
      final l = context.l10n;
      final locale = Localizations.localeOf(context).toString();
      final scheme = Theme.of(context).colorScheme;
      content = Container(
        key: const ValueKey('wc-conflict-banner'),
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c == null
              ? scheme.surfaceContainerHighest
              : hasMoveErrors(c)
              ? scheme.errorContainer
              : c.isEmpty
              ? Colors.green.withValues(alpha: 0.15)
              : Colors.orange.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: c == null
            ? Text(l.planningChecking)
            : c.isEmpty
            ? Text(l.planningNoConflicts)
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final x in c)
                    Text('• ${productionConflictText(l, x, locale)}'),
                ],
              ),
      );
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: content,
    );
  }

  Widget _wide(ProductionPlanningBoard b, bool canMove) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final centres = {for (final c in b.centres) c.id: c};
    return LayoutBuilder(
      builder: (context, box) {
        final days = _days;
        final available = box.maxWidth - _lateWidth - boardLabelWidth - 24;
        final dayWidth = (available / 7).clamp(_minDayWidth, 2000.0);
        final axis = BoardAxis(
          startMinute: workCentreAxisStart,
          endMinute: workCentreAxisEnd,
          pxPerMinute: dayWidth / (workCentreAxisEnd - workCentreAxisStart),
          snapMinutes: 60,
        );
        final dayFmt = DateFormat('EEE d/M', locale);
        return Row(
          children: [
            Expanded(
              child: ResourceBoard(
                days: days,
                rows: workCentreRows(b, days),
                items: workCentreItems(b, canMove: canMove),
                axis: axis,
                dayHeader: dayFmt.format,
                preview: _preview,
                onPreview: _onPreview,
                onPreviewEnd: _clearPreview,
                onDrop: _onDrop,
                onTapItem: (i) => _open(i.data as ProductionBoardOperation),
                rowTrailing: (row) {
                  final pct = utilisation(centres[row.id]!);
                  return pct == null
                      ? const SizedBox.shrink()
                      : Tooltip(
                          message: l.productionBoardUtilisation('$pct'),
                          child: Text(
                            '$pct%',
                            key: ValueKey('wc-util-${row.id}'),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: pct > 100 ? Colors.red : null,
                                  fontWeight: pct > 100
                                      ? FontWeight.bold
                                      : null,
                                ),
                          ),
                        );
                },
              ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(width: _lateWidth, child: _latePanel(b)),
          ],
        );
      },
    );
  }

  /// Operations planned to end before this week: still to do, listed here instead of on the grid.
  Widget _latePanel(ProductionPlanningBoard b) {
    final l = context.l10n;
    final late = [
      for (final o in b.operations)
        if (o.lateValue) o,
    ];
    final fmt = DateFormat('d MMM', Localizations.localeOf(context).toString());
    final names = {for (final c in b.centres) c.id: c.code};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            l.productionBoardLate,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: late.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(l.productionBoardNoLate),
                )
              : ListView(
                  key: const ValueKey('wc-late'),
                  children: [
                    for (final o in late)
                      ListTile(
                        dense: true,
                        title: Text('${o.orderNumber} · ${o.name}'),
                        subtitle: Text(
                          '${names[o.workCentreId] ?? ''} · ${fmt.format(o.plannedEnd)}',
                        ),
                        onTap: () => _open(o),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// A phone has no room for a grid: the work centres with what is planned on them, by day.
  Widget _agenda(ProductionPlanningBoard b) {
    final l = context.l10n;
    final fmt = DateFormat(
      'EEE d MMM',
      Localizations.localeOf(context).toString(),
    );
    return ListView(
      key: const ValueKey('wc-agenda'),
      children: [
        for (final c in b.centres) ...[
          ListTile(
            title: Text('${c.code} · ${c.name}'),
            trailing: Text(
              utilisation(c) == null ? '' : '${utilisation(c)}%',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          for (final o in b.operations)
            if (o.workCentreId == c.id)
              ListTile(
                dense: true,
                title: Text('${o.orderNumber} · ${o.name}'),
                subtitle: Text(
                  '${fmt.format(o.plannedStart)} – ${fmt.format(o.plannedEnd)} · ${o.plannedMinutes} min',
                ),
                trailing: o.lateValue ? Text(l.productionBoardLate) : null,
                onTap: () => _open(o),
              ),
          const Divider(height: 1),
        ],
      ],
    );
  }
}
