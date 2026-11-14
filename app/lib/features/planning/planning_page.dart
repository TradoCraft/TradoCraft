import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'agenda_view.dart';
import 'backlog_panel.dart';
import 'board_model.dart';
import 'planning_actions.dart';
import 'planning_adapter.dart';
import 'resource_board.dart';
import 'schedule_dialog.dart';
import '../../shared/app_icons.dart';

const double _backlogWidth = 300;
const double _phoneWidth = 720;
const double _minDayWidth = 200;

/// The planner's board: technicians as rows, days as columns, jobs as blocks you drag. On a
/// phone it falls back to an agenda of the day.
class PlanningPage extends ConsumerStatefulWidget {
  const PlanningPage({super.key, this.initialDay});

  /// The day to start on (today when empty).
  final DateTime? initialDay;

  @override
  ConsumerState<PlanningPage> createState() => _PlanningPageState();
}

class _PlanningPageState extends ConsumerState<PlanningPage> {
  bool _week = true;
  late DateTime _anchor = dateOnly(widget.initialDay ?? DateTime.now());
  String? _skill;
  Future<Board>? _board;

  BoardPreview? _preview;
  List<Conflict>? _previewConflicts;
  Timer? _debounce;
  int _token = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  List<DateTime> _days(bool week) {
    if (!week) return [_anchor];
    final monday = _anchor.subtract(Duration(days: _anchor.weekday - 1));
    return [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
  }

  void _reload(bool week) {
    final days = _days(week);
    setState(() {
      _board = ref
          .read(apiProvider)
          .planning
          .getPlanningBoard(from: days.first, to: days.last);
    });
  }

  void _move(int direction, bool week) {
    _anchor = _anchor.add(Duration(days: direction * (week ? 7 : 1)));
    _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day);
    _reload(week);
  }

  PlanningActions _actions(Board b) => PlanningActions(
    ref.read(apiProvider),
    technicianNames: {for (final t in b.technicians) t.userId: t.displayName},
    skillNames: {for (final s in b.skills) s.id: s.name},
  );

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

  /// While dragging: show the ghost at once and check the placement shortly after the pointer rests.
  void _onPreview(Board b, BoardDrop drop) {
    final job = drop.data.payload as BoardJob;
    final token = ++_token;
    _debounce?.cancel();
    setState(() {
      _preview = BoardPreview(
        rowId: drop.rowId,
        start: drop.start,
        end: drop.end,
      );
      _previewConflicts = null;
    });
    _debounce = Timer(const Duration(milliseconds: 120), () async {
      try {
        final c = await _actions(b).check(
          job.id,
          techniciansAfterDrop(job, drop.data.fromRowId, drop.rowId),
          drop.start,
          drop.end,
        );
        if (!mounted || token != _token) return;
        setState(() {
          _previewConflicts = c;
          _preview = BoardPreview(
            rowId: drop.rowId,
            start: drop.start,
            end: drop.end,
            color: hasErrors(c)
                ? Colors.red
                : (c.isEmpty ? Colors.green : Colors.orange),
          );
        });
      } catch (_) {
        // The check is a courtesy; saving checks again.
      }
    });
  }

  Future<void> _onDrop(Board b, BoardDrop drop, bool week) async {
    final job = drop.data.payload as BoardJob;
    _clearPreview();
    final ok = await _actions(b).save(
      context,
      job.id,
      techniciansAfterDrop(job, drop.data.fromRowId, drop.rowId),
      drop.start,
      drop.end,
    );
    if (ok && mounted) _reload(week);
  }

  Future<void> _plan(Board b, BoardJob job, bool week) async {
    final ok = await showScheduleDialog(
      context,
      board: b,
      job: job,
      actions: _actions(b),
    );
    if (ok && mounted) _reload(week);
  }

  Future<void> _open(BoardJob job, bool week) async {
    await context.push('/jobs/${job.id}');
    if (mounted) _reload(week);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions ?? const [];
    final phone = MediaQuery.sizeOf(context).width < _phoneWidth;
    final week = _week && !phone;
    _board ??= () {
      final days = _days(week);
      return ref
          .read(apiProvider)
          .planning
          .getPlanningBoard(from: days.first, to: days.last);
    }();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l.planningTitle),
        actions: [
          if (perms.contains('planning.write'))
            TextButton.icon(
              icon: const Icon(AppIcons.tune),
              label: Text(l.planningSettingsTitle),
              onPressed: () => context.push('/planning/settings'),
            ),
        ],
      ),
      body: FutureBuilder<Board>(
        future: _board,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(errorMessage(s.error!)),
                  TextButton(
                    onPressed: () => _reload(week),
                    child: Text(l.retry),
                  ),
                ],
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final b = s.data!;
          return Column(
            children: [
              _toolbar(context, b, week, phone),
              _banner(context, b),
              Expanded(child: phone ? _agenda(b, week) : _wide(b, week)),
            ],
          );
        },
      ),
    );
  }

  Widget _toolbar(BuildContext context, Board b, bool week, bool phone) {
    final l = context.l10n;
    final days = _days(week);
    final fmt = DateFormat('d MMM', Localizations.localeOf(context).toString());
    final label = week
        ? '${fmt.format(days.first)} – ${fmt.format(days.last)}'
        : DateFormat(
            'EEE d MMM',
            Localizations.localeOf(context).toString(),
          ).format(_anchor);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          IconButton(
            key: const ValueKey('prev'),
            tooltip: l.planningPrevious,
            icon: const Icon(AppIcons.chevronLeft),
            onPressed: () => _move(-1, week),
          ),
          OutlinedButton(
            key: const ValueKey('today'),
            onPressed: () {
              _anchor = dateOnly(DateTime.now());
              _reload(week);
            },
            child: Text(l.planningToday),
          ),
          IconButton(
            key: const ValueKey('next'),
            tooltip: l.planningNext,
            icon: const Icon(AppIcons.chevronRight),
            onPressed: () => _move(1, week),
          ),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          if (!phone)
            SegmentedButton<bool>(
              key: const ValueKey('mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(l.planningDay)),
                ButtonSegment(value: true, label: Text(l.planningWeek)),
              ],
              selected: {week},
              onSelectionChanged: (v) {
                _week = v.first;
                _reload(_week);
              },
            ),
          DropdownButton<String?>(
            key: const ValueKey('skill-filter'),
            value: _skill,
            hint: Text(l.planningSkillFilter),
            items: [
              DropdownMenuItem(value: null, child: Text(l.planningAllSkills)),
              for (final s in b.skills)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _skill = v),
          ),
        ],
      ),
    );
  }

  /// The conflicts of the placement under the pointer while dragging.
  Widget _banner(BuildContext context, Board b) {
    final c = _previewConflicts;
    if (_preview == null) return const SizedBox.shrink();
    final l = context.l10n;
    final names = {for (final t in b.technicians) t.userId: t.displayName};
    final skills = {for (final s in b.skills) s.id: s.name};
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('planning-conflict-banner'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c == null
            ? scheme.surfaceContainerHighest
            : hasErrors(c)
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
                  Text('• ${conflictText(l, x, names, skills)}'),
              ],
            ),
    );
  }

  List<BoardJob> _backlog(Board b) => [
    for (final j in b.backlog)
      if (_skill == null || j.requiredSkillIds.contains(_skill)) j,
  ];

  Widget _agenda(Board b, bool week) => AgendaView(
    board: b,
    day: _anchor,
    skillId: _skill,
    onOpen: (j) => _open(j, week),
    onPlan: (j) => _plan(b, j, week),
  );

  Widget _wide(Board b, bool week) {
    final l = context.l10n;
    return LayoutBuilder(
      builder: (context, box) {
        final days = _days(week);
        final (startMin, endMin) = axisRange(b);
        final available = box.maxWidth - _backlogWidth - boardLabelWidth - 24;
        final dayWidth = week
            ? (available / 7).clamp(_minDayWidth, 2000.0)
            : available.clamp(_minDayWidth * 2, 4000.0);
        final axis = BoardAxis(
          startMinute: startMin,
          endMinute: endMin,
          pxPerMinute: dayWidth / (endMin - startMin),
        );
        final rows = boardRows(b, days, l, skillId: _skill);
        final items = boardItems(b, {for (final r in rows) r.id});
        final dayFmt = DateFormat(
          'EEE d/M',
          Localizations.localeOf(context).toString(),
        );
        return Row(
          children: [
            Expanded(
              child: rows.isEmpty
                  ? Center(child: Text(l.planningNoTechnicians))
                  : ResourceBoard(
                      days: days,
                      rows: rows,
                      items: items,
                      axis: axis,
                      dayHeader: dayFmt.format,
                      preview: _preview,
                      onPreview: (d) => _onPreview(b, d),
                      onPreviewEnd: _clearPreview,
                      onDrop: (d) => _onDrop(b, d, week),
                      onTapItem: (i) => _open(i.data as BoardJob, week),
                    ),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: _backlogWidth,
              child: BacklogPanel(
                board: b,
                jobs: _backlog(b),
                pxPerMinute: axis.pxPerMinute,
                onPlan: (j) => _plan(b, j, week),
                onOpen: (j) => _open(j, week),
              ),
            ),
          ],
        );
      },
    );
  }
}
