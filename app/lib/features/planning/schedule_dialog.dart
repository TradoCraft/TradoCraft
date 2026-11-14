import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import 'board_model.dart';
import 'planning_actions.dart';
import 'planning_adapter.dart';
import '../../shared/app_icons.dart';

final _dateFormat = DateFormat('EEE dd/MM');
final _timeFormat = DateFormat('HH:mm');

/// Schedules one job without dragging: pick technicians, day and times, see the conflicts, or
/// take one of the suggestions. Returns true when the job was scheduled.
Future<bool> showScheduleDialog(
  BuildContext context, {
  required Board board,
  required BoardJob job,
  required PlanningActions actions,
}) async {
  final done = await showDialog<bool>(
    context: context,
    builder: (_) => _ScheduleDialog(board: board, job: job, actions: actions),
  );
  return done == true;
}

class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({
    required this.board,
    required this.job,
    required this.actions,
  });
  final Board board;
  final BoardJob job;
  final PlanningActions actions;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late DateTime _day;
  late TimeOfDay _start;
  late TimeOfDay _end;
  late Set<String> _techs;
  List<Conflict>? _conflicts;
  List<SuggestionOut>? _suggestions;
  int _token = 0;
  bool _saving = false;
  late Set<String> _required;
  bool _skillsChanged = false;

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    final s = j.scheduledStart?.toLocal();
    if (s != null) {
      _day = dateOnly(s);
      _start = TimeOfDay.fromDateTime(s);
      _end = TimeOfDay.fromDateTime(
        j.scheduledEnd?.toLocal() ?? s.add(jobDuration(j, widget.board)),
      );
    } else {
      var d = dateOnly(DateTime.now());
      while (d.weekday > 5) {
        d = d.add(const Duration(days: 1));
      }
      _day = d;
      _start = const TimeOfDay(hour: 9, minute: 0);
      final end = DateTime(2000, 1, 1, 9).add(jobDuration(j, widget.board));
      _end = TimeOfDay(hour: end.hour, minute: end.minute);
    }
    _techs = {...j.technicianIds};
    _required = {...j.requiredSkillIds};
    _check();
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  bool get _valid => _techs.isNotEmpty && _at(_end).isAfter(_at(_start));

  Future<void> _check() async {
    final token = ++_token;
    if (!_valid) {
      setState(() => _conflicts = null);
      return;
    }
    setState(() => _conflicts = null);
    try {
      final c = await widget.actions.check(
        widget.job.id,
        _techs.toList(),
        _at(_start),
        _at(_end),
      );
      if (mounted && token == _token) setState(() => _conflicts = c);
    } catch (_) {
      if (mounted && token == _token) setState(() => _conflicts = const []);
    }
  }

  Future<void> _toggleSkill(String id, bool on) async {
    final next = {..._required};
    on ? next.add(id) : next.remove(id);
    try {
      await widget.actions.api.planning.setJobSkills(
        id: widget.job.id,
        body: JobSkillsInput(skillIds: next.toList()),
      );
      setState(() {
        _required = next;
        _skillsChanged = true;
      });
      _check();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMessage(e))));
      }
    }
  }

  Future<void> _loadSuggestions() async {
    final from = dateOnly(DateTime.now());
    final s = await widget.actions.api.planning.suggestSlots(
      jobId: widget.job.id,
      from: from,
      to: from.add(const Duration(days: 13)),
    );
    if (mounted) setState(() => _suggestions = s.take(5).toList());
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (d != null) {
      setState(() => _day = dateOnly(d));
      _check();
    }
  }

  Future<void> _pickTime(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _start : _end,
    );
    if (t != null) {
      setState(() => start ? _start = t : _end = t);
      _check();
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.actions.save(
      context,
      widget.job.id,
      _techs.toList(),
      _at(_start),
      _at(_end),
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final names = widget.actions.technicianNames;
    return AlertDialog(
      title: Text(l.planningScheduleJob(widget.job.number)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.job.title, style: theme.textTheme.titleSmall),
              const SizedBox(height: 12),
              Text(l.technicians, style: theme.textTheme.labelLarge),
              Wrap(
                spacing: 8,
                children: [
                  for (final t in widget.board.technicians)
                    FilterChip(
                      key: ValueKey('tech-${t.userId}'),
                      label: Text(t.displayName),
                      selected: _techs.contains(t.userId),
                      onSelected: (v) {
                        setState(
                          () => v
                              ? _techs.add(t.userId)
                              : _techs.remove(t.userId),
                        );
                        _check();
                      },
                    ),
                ],
              ),
              if (widget.board.skills.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l.planningRequiredSkills,
                  style: theme.textTheme.labelLarge,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in widget.board.skills)
                      FilterChip(
                        key: ValueKey('skill-${s.id}'),
                        label: Text(s.name),
                        selected: _required.contains(s.id),
                        onSelected: (v) => _toggleSkill(s.id, v),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('pick-day'),
                    icon: const Icon(AppIcons.event),
                    label: Text(_dateFormat.format(_day)),
                    onPressed: _pickDay,
                  ),
                  OutlinedButton(
                    onPressed: () => _pickTime(true),
                    child: Text(_timeFormat.format(_at(_start))),
                  ),
                  OutlinedButton(
                    onPressed: () => _pickTime(false),
                    child: Text(_timeFormat.format(_at(_end))),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _conflictList(context, names),
              const Divider(height: 24),
              Row(
                children: [
                  Text(
                    l.planningSuggestions,
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    key: const ValueKey('load-suggestions'),
                    onPressed: _loadSuggestions,
                    child: Text(l.planningShowSuggestions),
                  ),
                ],
              ),
              if (_suggestions != null && _suggestions!.isEmpty)
                Text(l.planningNoSuggestions),
              for (final s in _suggestions ?? const <SuggestionOut>[])
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.technicianName),
                  subtitle: Text(
                    '${_dateFormat.format(s.scheduledStart.toLocal())} ${_timeFormat.format(s.scheduledStart.toLocal())}–${_timeFormat.format(s.scheduledEnd.toLocal())}'
                    '${s.missingSkillIds.isEmpty ? '' : ' · ${l.planningMissingSkills(s.missingSkillIds.length)}'}',
                  ),
                  onTap: () {
                    final st = s.scheduledStart.toLocal(),
                        en = s.scheduledEnd.toLocal();
                    setState(() {
                      _day = dateOnly(st);
                      _start = TimeOfDay.fromDateTime(st);
                      _end = TimeOfDay.fromDateTime(en);
                      _techs = {s.technicianId};
                    });
                    _check();
                  },
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _skillsChanged),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('save-schedule'),
          onPressed: _valid && !_saving ? _save : null,
          child: Text(l.save),
        ),
      ],
    );
  }

  Widget _conflictList(BuildContext context, Map<String, String> names) {
    final l = context.l10n;
    final skills = {for (final s in widget.board.skills) s.id: s.name};
    if (_conflicts == null) return Text(_valid ? l.planningChecking : '');
    if (_conflicts!.isEmpty) return Text(l.planningNoConflicts);
    return Column(
      key: const ValueKey('schedule-conflicts'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in _conflicts!)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                c.severity == Severity.error
                    ? AppIcons.error
                    : AppIcons.warningAmber,
                size: 18,
                color: c.severity == Severity.error
                    ? Colors.red
                    : Colors.orange.shade800,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(conflictText(l, c, names, skills))),
            ],
          ),
      ],
    );
  }
}
