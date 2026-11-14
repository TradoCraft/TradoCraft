import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../planning/board_model.dart' show dateOnly;
import '../planning/planning_adapter.dart' show clockText, minutesOfText;
import 'production_page.dart';

/// The work centres of the company, with their working hours.
final workCentresProvider = FutureProvider.autoDispose<List<WorkCentre>>(
  (ref) => ref.watch(apiProvider).production.listWorkCentres(),
);

/// The closures that have not ended yet (work centres and the whole plant).
final workCentreClosuresProvider =
    FutureProvider.autoDispose<List<WorkCentreClosure>>(
      (ref) => ref
          .watch(apiProvider)
          .production
          .listWorkCentreClosures(from: dateOnly(DateTime.now())),
    );

/// The work centres: machines, benches and crews that operations run on. The administrator keeps
/// them and their hours (`production.admin`); planners enter closures (`production.write`).
class WorkCentresPage extends ConsumerWidget {
  const WorkCentresPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final admin = perms.contains('production.admin');
    final canClose = perms.contains('production.write');
    final canCost = perms.contains('inventory.cost');
    final list = ref.watch(workCentresProvider);
    final locale = Localizations.localeOf(context).toString();
    Future<void> edit([WorkCentre? w]) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _WorkCentreDialog(existing: w, canCost: canCost),
      );
      if (saved == true && context.mounted) ref.invalidate(workCentresProvider);
    }

    Future<void> hours(WorkCentre w) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _HoursDialog(centre: w),
      );
      if (saved == true && context.mounted) ref.invalidate(workCentresProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l.productionWorkCentres),
        actions: [
          IconButton(
            key: const ValueKey('closures'),
            tooltip: l.productionClosures,
            icon: const Icon(AppIcons.eventBusy),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _ClosuresDialog(canEdit: canClose),
            ),
          ),
        ],
      ),
      floatingActionButton: admin
          ? FloatingActionButton.extended(
              key: const ValueKey('add-work-centre'),
              onPressed: edit,
              icon: const Icon(AppIcons.add),
              label: Text(l.productionWorkCentreAdd),
            )
          : null,
      body: !perms.contains('production.read')
          ? Center(child: Text(l.noPermission))
          : list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(errorMessage(e))),
              data: (centres) => centres.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(l.productionWorkCentreEmpty),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        for (final w in centres)
                          ListTile(
                            key: ValueKey('work-centre-${w.id}'),
                            title: Text('${w.code} · ${w.name}'),
                            subtitle: Text(
                              '${[if (!w.active) l.inactive, w.divisionName ?? l.productionNoDivision, l.productionWorkCentreUnits(w.capacity.toString()), if (w.costPerHour != null) '${l.productionWorkCentreCost}: ${number(w.costPerHour)}', l.productionWorkCentreOpenOps(w.openOperations.toString())].join(' · ')}\n${_hoursSummary(w.hours, locale, l.productionHoursDefault)}',
                            ),
                            isThreeLine: true,
                            trailing: admin
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        key: ValueKey('hours-${w.id}'),
                                        tooltip: l.productionWorkingHours,
                                        icon: const Icon(AppIcons.schedule),
                                        onPressed: () => hours(w),
                                      ),
                                      IconButton(
                                        tooltip: l.edit,
                                        icon: const Icon(AppIcons.edit),
                                        onPressed: () => edit(w),
                                      ),
                                      IconButton(
                                        key: ValueKey('delete-${w.id}'),
                                        tooltip: l.remove,
                                        icon: const Icon(AppIcons.delete),
                                        onPressed: () async {
                                          await runAction(
                                            context,
                                            () => ref
                                                .read(apiProvider)
                                                .production
                                                .deleteWorkCentre(id: w.id),
                                          );
                                          if (!context.mounted) return;
                                          ref.invalidate(workCentresProvider);
                                        },
                                      ),
                                    ],
                                  )
                                : null,
                          ),
                      ],
                    ),
            ),
    );
  }
}

/// "Mon 08:00–12:00, 13:00–17:00 · Tue ...", or the note that the default week applies.
String _hoursSummary(
  List<WorkCentreHoursSlot> slots,
  String locale,
  String fallback,
) {
  if (slots.isEmpty) return fallback;
  final days = <int, List<String>>{};
  for (final s in slots) {
    (days[s.weekday] ??= []).add(
      '${clockText(minutesOfText(s.startTime))}–${clockText(minutesOfText(s.endTime))}',
    );
  }
  final keys = days.keys.toList()..sort();
  return [
    for (final d in keys)
      // 2026-11-02 is a Monday.
      '${DateFormat('E', locale).format(DateTime(2026, 11, 1 + d))} ${days[d]!.join(', ')}',
  ].join(' · ');
}

class _WorkCentreDialog extends ConsumerStatefulWidget {
  const _WorkCentreDialog({this.existing, required this.canCost});
  final WorkCentre? existing;
  final bool canCost;

  @override
  ConsumerState<_WorkCentreDialog> createState() => _WorkCentreDialogState();
}

class _WorkCentreDialogState extends ConsumerState<_WorkCentreDialog> {
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _capacity = TextEditingController(
    text: (widget.existing?.capacity ?? 1).toString(),
  );
  late final _cost = TextEditingController(text: widget.existing?.costPerHour);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late bool _active = widget.existing?.active ?? true;
  late String? _division = widget.existing?.divisionId;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _capacity.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final e = widget.existing;
    final body = WorkCentreInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      divisionId: _division,
      capacity: int.tryParse(_capacity.text.trim()) ?? 1,
      costPerHour: widget.canCost ? parseDecimalInput(_cost.text) : null,
      active: _active,
      sortOrder: e?.sortOrder ?? 0,
      notes: _notes.text.trim(),
    );
    final api = ref.read(apiProvider).production;
    try {
      if (e == null) {
        await api.createWorkCentre(body: body);
      } else {
        await api.updateWorkCentre(id: e.id, body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final divisions = ref.watch(divisionsProvider).value ?? const <Division>[];
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? l.productionWorkCentreAdd
            : l.productionWorkCentreEdit,
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('wc-code'),
                controller: _code,
                decoration: InputDecoration(labelText: l.code),
              ),
              TextField(
                key: const ValueKey('wc-name'),
                controller: _name,
                decoration: InputDecoration(labelText: l.name),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                key: ValueKey('wc-division-${divisions.length}'),
                initialValue: divisions.any((d) => d.id == _division)
                    ? _division
                    : null,
                decoration: InputDecoration(labelText: l.productionDivision),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l.productionNoDivision),
                  ),
                  for (final d in divisions.where(
                    (d) => d.active || d.id == widget.existing?.divisionId,
                  ))
                    DropdownMenuItem(value: d.id, child: Text(d.name)),
                ],
                onChanged: (v) => setState(() => _division = v),
              ),
              TextField(
                key: const ValueKey('wc-capacity'),
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l.productionWorkCentreCapacity,
                ),
              ),
              if (widget.canCost)
                TextField(
                  key: const ValueKey('wc-cost'),
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l.productionWorkCentreCost,
                  ),
                ),
              TextField(
                key: const ValueKey('wc-notes'),
                controller: _notes,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(labelText: l.notes),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.active),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('wc-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// The opening hours of one work centre: blocks per weekday. No blocks: the default week.
class _HoursDialog extends ConsumerStatefulWidget {
  const _HoursDialog({required this.centre});
  final WorkCentre centre;

  @override
  ConsumerState<_HoursDialog> createState() => _HoursDialogState();
}

class _HoursDialogState extends ConsumerState<_HoursDialog> {
  late final Map<int, List<(int, int)>> _blocks = {
    for (final s in widget.centre.hours) s.weekday: [],
  };
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final s in widget.centre.hours) {
      _blocks[s.weekday]!.add((
        minutesOfText(s.startTime),
        minutesOfText(s.endTime),
      ));
    }
  }

  Future<void> _pickTime(int weekday, int index, bool start) async {
    final cur = _blocks[weekday]![index];
    final m = start ? cur.$1 : cur.$2;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
    );
    if (t == null || !mounted) return;
    final v = t.hour * 60 + t.minute;
    setState(
      () => _blocks[weekday]![index] = start ? (v, cur.$2) : (cur.$1, v),
    );
  }

  Future<void> _save() async {
    try {
      await ref
          .read(apiProvider)
          .production
          .setWorkCentreHours(
            id: widget.centre.id,
            body: WorkCentreHoursInput(
              slots: [
                for (final e in _blocks.entries)
                  for (final b in e.value)
                    WorkCentreHoursSlot(
                      weekday: e.key,
                      startTime: '${clockText(b.$1)}:00',
                      endTime: '${clockText(b.$2)}:00',
                    ),
              ],
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final none = _blocks.values.every((b) => b.isEmpty);
    return AlertDialog(
      title: Text('${l.productionWorkingHours} · ${widget.centre.code}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (none)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(l.productionHoursDefault),
                ),
              for (var wd = 1; wd <= 7; wd++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          // 2026-11-02 is a Monday.
                          child: Text(
                            DateFormat(
                              'EEEE',
                              locale,
                            ).format(DateTime(2026, 11, 1 + wd)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (var i = 0; i < (_blocks[wd]?.length ?? 0); i++)
                              InputChip(
                                key: ValueKey('wc-block-$wd-$i'),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: () => _pickTime(wd, i, true),
                                      child: Text(
                                        clockText(_blocks[wd]![i].$1),
                                      ),
                                    ),
                                    const Text(' – '),
                                    InkWell(
                                      onTap: () => _pickTime(wd, i, false),
                                      child: Text(
                                        clockText(_blocks[wd]![i].$2),
                                      ),
                                    ),
                                  ],
                                ),
                                onDeleted: () =>
                                    setState(() => _blocks[wd]!.removeAt(i)),
                              ),
                            ActionChip(
                              key: ValueKey('wc-add-block-$wd'),
                              avatar: const Icon(AppIcons.add, size: 16),
                              label: Text(l.productionHoursAddBlock),
                              onPressed: () => setState(() {
                                final list = _blocks[wd] ??= [];
                                list.add(
                                  list.isEmpty
                                      ? (8 * 60, 12 * 60)
                                      : (13 * 60, 17 * 60),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('hours-save'),
          onPressed: _save,
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Closures that have not ended: maintenance of a work centre, holidays of the whole plant.
class _ClosuresDialog extends ConsumerStatefulWidget {
  const _ClosuresDialog({required this.canEdit});
  final bool canEdit;

  @override
  ConsumerState<_ClosuresDialog> createState() => _ClosuresDialogState();
}

class _ClosuresDialogState extends ConsumerState<_ClosuresDialog> {
  String? _centre; // null: the whole plant
  String _kind = 'maintenance';
  DateTime _from = dateOnly(DateTime.now());
  DateTime _to = dateOnly(DateTime.now());
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    setState(() {
      if (from) {
        _from = dateOnly(d);
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = dateOnly(d);
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  Future<void> _add() async {
    try {
      await ref
          .read(apiProvider)
          .production
          .createWorkCentreClosure(
            body: WorkCentreClosureInput(
              workCentreId: _centre,
              fromDate: _from,
              toDate: _to,
              kind: _kind,
              note: _note.text.trim(),
            ),
          );
      if (!mounted) return;
      _note.clear();
      ref.invalidate(workCentreClosuresProvider);
      setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final closures = ref.watch(workCentreClosuresProvider);
    final centres =
        ref.watch(workCentresProvider).value ?? const <WorkCentre>[];
    String kindLabel(String k) => switch (k) {
      'maintenance' => l.productionClosureMaintenance,
      'holiday' => l.productionClosureHoliday,
      _ => l.productionClosureOther,
    };
    return AlertDialog(
      title: Text(l.productionClosures),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              closures.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text(errorMessage(e)),
                data: (list) => list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(l.productionClosureEmpty),
                      )
                    : Column(
                        children: [
                          for (final c in list)
                            ListTile(
                              key: ValueKey('closure-${c.id}'),
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                '${c.workCentreCode ?? l.productionClosureWholePlant} · ${kindLabel(c.kind)}',
                              ),
                              subtitle: Text(
                                [
                                  c.fromDate == c.toDate
                                      ? date(c.fromDate)
                                      : '${date(c.fromDate)} – ${date(c.toDate)}',
                                  if (c.note.isNotEmpty) c.note,
                                ].join(' · '),
                              ),
                              trailing: widget.canEdit
                                  ? IconButton(
                                      key: ValueKey('delete-closure-${c.id}'),
                                      tooltip: l.remove,
                                      icon: const Icon(AppIcons.delete),
                                      onPressed: () async {
                                        await runAction(
                                          context,
                                          () => ref
                                              .read(apiProvider)
                                              .production
                                              .deleteWorkCentreClosure(
                                                id: c.id,
                                              ),
                                        );
                                        if (!mounted) return;
                                        ref.invalidate(
                                          workCentreClosuresProvider,
                                        );
                                      },
                                    )
                                  : null,
                            ),
                        ],
                      ),
              ),
              if (widget.canEdit) ...[
                const Divider(),
                Text(
                  l.productionClosureAdd,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                DropdownButtonFormField<String?>(
                  key: const ValueKey('closure-centre'),
                  initialValue: _centre,
                  decoration: InputDecoration(
                    labelText: l.productionWorkCentres,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l.productionClosureWholePlant),
                    ),
                    for (final w in centres)
                      DropdownMenuItem(
                        value: w.id,
                        child: Text('${w.code} · ${w.name}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _centre = v),
                ),
                DropdownButtonFormField<String>(
                  key: const ValueKey('closure-kind'),
                  initialValue: _kind,
                  decoration: InputDecoration(
                    labelText: l.productionClosureKind,
                  ),
                  items: [
                    for (final k in const ['maintenance', 'holiday', 'other'])
                      DropdownMenuItem(value: k, child: Text(kindLabel(k))),
                  ],
                  onChanged: (v) => setState(() => _kind = v ?? 'other'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      key: const ValueKey('closure-from'),
                      onPressed: () => _pick(true),
                      child: Text('${l.from}: ${date(_from)}'),
                    ),
                    OutlinedButton(
                      key: const ValueKey('closure-to'),
                      onPressed: () => _pick(false),
                      child: Text('${l.to}: ${date(_to)}'),
                    ),
                  ],
                ),
                TextField(
                  key: const ValueKey('closure-note'),
                  controller: _note,
                  decoration: InputDecoration(labelText: l.notes),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    key: const ValueKey('closure-add'),
                    onPressed: _add,
                    icon: const Icon(AppIcons.add),
                    label: Text(l.add),
                  ),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.close),
        ),
      ],
    );
  }
}
