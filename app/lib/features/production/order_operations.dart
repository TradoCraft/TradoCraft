import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../planning/board_model.dart' show dateOnly;
import 'work_centres_page.dart' show workCentresProvider;

/// The operations of a production order (the routing as it was at release): where each one runs,
/// when it is planned, and what was worked. The floor starts and finishes them (`production.run`),
/// planners move them and schedule the rest again (`production.write`). Shows nothing for an order
/// without operations.
class OrderOperations extends ConsumerWidget {
  const OrderOperations({
    super.key,
    required this.order,
    required this.canRun,
    required this.canWrite,
    required this.busy,
    required this.run,
  });

  final ProductionOrder order;
  final bool canRun;
  final bool canWrite;
  final bool busy;

  /// Runs an action that returns the changed order and shows it.
  final Future<void> Function(Future<ProductionOrder> Function() action) run;

  ProductionClient _api(WidgetRef ref) => ref.read(apiProvider).production;

  String _dates(ProductionOperation o) => o.plannedStart == o.plannedEnd
      ? date(o.plannedStart)
      : '${date(o.plannedStart)} – ${date(o.plannedEnd)}';

  Future<void> _finish(
    BuildContext context,
    WidgetRef ref,
    ProductionOperation o,
  ) async {
    final body = await showDialog<ProductionOperationFinish>(
      context: context,
      builder: (_) => _FinishDialog(operation: o),
    );
    if (body == null) return;
    await run(
      () => _api(ref).finishProductionOperation(
        id: order.id,
        operationId: o.id,
        body: body,
      ),
    );
  }

  Future<void> _move(
    BuildContext context,
    WidgetRef ref,
    ProductionOperation o,
  ) async {
    final body = await showDialog<ProductionOperationUpdate>(
      context: context,
      builder: (_) => _MoveDialog(operation: o),
    );
    if (body == null) return;
    await run(
      () => _api(ref).updateProductionOperation(
        id: order.id,
        operationId: o.id,
        body: body,
      ),
    );
  }

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final now = dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      helpText: context.l10n.productionStartFrom,
      initialDate: now,
      firstDate: now,
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    await run(
      () => _api(ref).scheduleProductionOrder(
        id: order.id,
        body: ProductionScheduleInput(startDate: dateOnly(d)),
      ),
    );
  }

  IconData _icon(String status) => switch (status) {
    'in_progress' => AppIcons.playArrow,
    'done' => AppIcons.checkCircle,
    'skipped' => AppIcons.skipNext,
    _ => AppIcons.circleOutlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (order.operations.isEmpty) return const SizedBox.shrink();
    final l = context.l10n;
    final open = order.status == 'released' || order.status == 'in_progress';
    final anyPending = order.operations.any((o) => o.status == 'pending');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                l.productionOperations,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (open && canWrite && anyPending)
              TextButton.icon(
                key: const ValueKey('schedule-again'),
                onPressed: busy ? null : () => _schedule(context, ref),
                icon: const Icon(AppIcons.calendarToday),
                label: Text(l.productionScheduleAgain),
              ),
          ],
        ),
        for (final o in order.operations)
          ListTile(
            key: ValueKey('operation-${o.id}'),
            contentPadding: EdgeInsets.zero,
            leading: Icon(_icon(o.status)),
            title: Text('${o.position}. ${o.name}'),
            subtitle: Text(
              [
                '${o.workCentreCode} · ${l.productionOperationPlanned} ${minutesText(o.plannedMinutes)} · ${_dates(o)}',
                [
                  l.productionOperationStatus(o.status),
                  if (o.actualMinutes != null)
                    '${l.productionOperationWorked} ${minutesText(o.actualMinutes!)}',
                  if (o.completedByName != null)
                    l.productionOperationBy(o.completedByName!),
                ].join(' · '),
                if (o.notes.isNotEmpty) o.notes,
              ].join('\n'),
            ),
            isThreeLine: true,
            trailing: !open
                ? null
                : Wrap(
                    children: [
                      if (canRun && o.status == 'pending')
                        IconButton(
                          key: ValueKey('start-op-${o.id}'),
                          tooltip: l.productionOperationStart,
                          icon: const Icon(AppIcons.playArrow),
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => _api(ref).startProductionOperation(
                                    id: order.id,
                                    operationId: o.id,
                                  ),
                                ),
                        ),
                      if (canRun &&
                          (o.status == 'pending' || o.status == 'in_progress'))
                        IconButton(
                          key: ValueKey('finish-op-${o.id}'),
                          tooltip: l.productionOperationFinish,
                          icon: const Icon(AppIcons.check),
                          onPressed: busy
                              ? null
                              : () => _finish(context, ref, o),
                        ),
                      if (canRun &&
                          (o.status == 'done' || o.status == 'skipped'))
                        IconButton(
                          key: ValueKey('reopen-op-${o.id}'),
                          tooltip: l.productionOperationReopen,
                          icon: const Icon(AppIcons.undo),
                          onPressed: busy
                              ? null
                              : () => run(
                                  () => _api(ref).reopenProductionOperation(
                                    id: order.id,
                                    operationId: o.id,
                                  ),
                                ),
                        ),
                      if (canWrite &&
                          (o.status == 'pending' || o.status == 'in_progress'))
                        IconButton(
                          key: ValueKey('move-op-${o.id}'),
                          tooltip: l.productionOperationMove,
                          icon: const Icon(AppIcons.edit),
                          onPressed: busy ? null : () => _move(context, ref, o),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }
}

/// Asks for the minutes an operation took (default: the planned minutes) and an optional note.
class _FinishDialog extends StatefulWidget {
  const _FinishDialog({required this.operation});
  final ProductionOperation operation;

  @override
  State<_FinishDialog> createState() => _FinishDialogState();
}

class _FinishDialogState extends State<_FinishDialog> {
  late final _minutes = TextEditingController(
    text: widget.operation.plannedMinutes.toString(),
  );
  final _note = TextEditingController();

  @override
  void dispose() {
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text('${l.productionOperationFinish} · ${widget.operation.name}'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('finish-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l.productionOperationMinutes,
              ),
            ),
            TextField(
              key: const ValueKey('finish-note'),
              controller: _note,
              decoration: InputDecoration(labelText: l.notes),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('finish-save'),
          onPressed: () => Navigator.pop(
            context,
            ProductionOperationFinish(
              actualMinutes: int.tryParse(_minutes.text.trim()),
              note: _note.text.trim(),
            ),
          ),
          child: Text(l.productionOperationFinish),
        ),
      ],
    );
  }
}

/// Moves an operation to another work centre and/or other dates.
class _MoveDialog extends ConsumerStatefulWidget {
  const _MoveDialog({required this.operation});
  final ProductionOperation operation;

  @override
  ConsumerState<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends ConsumerState<_MoveDialog> {
  late String _centre = widget.operation.workCentreId;
  late DateTime _start = dateOnly(widget.operation.plannedStart);
  late DateTime _end = dateOnly(widget.operation.plannedEnd);

  Future<void> _pick(bool start) async {
    final d = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null) return;
    setState(() {
      if (start) {
        _start = dateOnly(d);
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = dateOnly(d);
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final centres = ref.watch(workCentresProvider).value ?? const [];
    return AlertDialog(
      title: Text('${l.productionOperationMove} · ${widget.operation.name}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('move-centre-${centres.length}'),
              initialValue: centres.any((w) => w.id == _centre)
                  ? _centre
                  : null,
              decoration: InputDecoration(labelText: l.productionWorkCentres),
              items: [
                for (final w in centres.where(
                  (w) => w.active || w.id == widget.operation.workCentreId,
                ))
                  DropdownMenuItem(
                    value: w.id,
                    enabled: w.active,
                    child: Text('${w.code} · ${w.name}'),
                  ),
              ],
              onChanged: (v) => setState(() => _centre = v ?? _centre),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  key: const ValueKey('move-start'),
                  onPressed: () => _pick(true),
                  child: Text('${l.from}: ${date(_start)}'),
                ),
                OutlinedButton(
                  key: const ValueKey('move-end'),
                  onPressed: () => _pick(false),
                  child: Text('${l.to}: ${date(_end)}'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          key: const ValueKey('move-save'),
          onPressed: () => Navigator.pop(
            context,
            ProductionOperationUpdate(
              workCentreId: _centre,
              plannedStart: _start,
              plannedEnd: _end,
            ),
          ),
          child: Text(l.save),
        ),
      ],
    );
  }
}
