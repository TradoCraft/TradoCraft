import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../planning/board_model.dart';
import 'complete_dialog.dart';
import 'order_operations.dart';
import 'production_page.dart';
import '../tutorial/targets.dart';

/// One production order: division, planned-ready date, the frozen components with what is
/// reserved, start, complete (backflush) and cancel.
class ProductionScreen extends ConsumerStatefulWidget {
  const ProductionScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<ProductionScreen> createState() => _ProductionScreenState();
}

class _ProductionScreenState extends ConsumerState<ProductionScreen> {
  ProductionOrder? _po;
  String? _error;
  bool _busy = false;
  bool _changed = false;
  String? _division;
  DateTime? _ready;
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final po = await ref.read(apiProvider).production.getOrder(id: widget.id);
      if (mounted) {
        setState(() {
          _show(po);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _show(ProductionOrder po) {
    _po = po;
    _division = po.divisionId;
    _ready = po.plannedReadyDate == null
        ? null
        : dateOnly(po.plannedReadyDate!);
    _notes.text = po.notes;
  }

  Future<void> _run(
    Future<ProductionOrder> Function() action, {
    String? success,
  }) async {
    setState(() => _busy = true);
    try {
      final po = await action();
      _changed = true;
      if (mounted) {
        setState(() => _show(po));
        if (success != null) _snack(success);
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  ProductionClient get _api => ref.read(apiProvider).production;

  Future<void> _save() => _run(
    () => _api.updateOrder(
      id: widget.id,
      body: UpdateProductionInput(
        divisionId: _division,
        plannedReadyDate: _ready,
        notes: _notes.text.trim(),
      ),
    ),
    success: context.l10n.saved,
  );

  Future<void> _pickReady() async {
    final now = dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _ready ?? now,
      firstDate: _ready != null && _ready!.isBefore(now) ? _ready! : now,
      lastDate: _ready != null && _ready!.isAfter(DateTime(now.year + 3))
          ? _ready!
          : DateTime(now.year + 3),
    );
    if (d != null) setState(() => _ready = dateOnly(d));
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    final reason = await askText(
      context,
      title: l.productionCancel,
      label: l.productionCancelReason,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(
      () => _api.cancelOrder(
        id: widget.id,
        body: CancelProductionInput(reason: reason.trim()),
      ),
    );
  }

  Future<void> _complete() async {
    final po = _po!;
    final done = await showDialog<ProductionOrder>(
      context: context,
      builder: (_) => CompleteDialog(order: po),
    );
    if (done != null && mounted) {
      _changed = true;
      setState(() => _show(done));
      _snack(context.l10n.productionCompleted);
    }
  }

  /// Releases a production order for what is still missing of a component that is built from a
  /// BOM; the server works out how much (required, less reserved, free and already under way).
  Future<void> _buildComponent(ProductionComponent c) async {
    final po = _po!;
    String? opened;
    await runAction(context, () async {
      final child = await _api.buildComponent(
        id: po.id,
        componentId: c.id,
        body: ProductionBuildComponentInput(),
      );
      opened = child.id;
    }, success: context.l10n.productionReleased);
    if (opened != null && mounted) {
      await context.push('/production/$opened');
      _load();
    }
  }

  Future<void> _pdf() async {
    final po = _po!;
    await runAction(context, () async {
      final bytes = await downloadBytes(
        ref.read(dioProvider),
        '/api/v1/production-orders/${po.id}/pdf',
      );
      await Printing.layoutPdf(
        name: '${po.number}.pdf',
        onLayout: (_) async => Uint8List.fromList(bytes),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final po = _po;
    if (po == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.production)),
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(onPressed: _load, child: Text(l.retry)),
                  ],
                ),
        ),
      );
    }
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final divisions = ref.watch(divisionsProvider).value ?? const <Division>[];
    final open = po.status == 'released' || po.status == 'in_progress';
    final canWrite = open && perms.contains('production.write');
    final canRun = open && perms.contains('production.run');
    final anyShort = po.components.any((c) => c.short);
    const gap = SizedBox(height: 12);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${po.number} · ${l.productionStatus(po.status)}'),
          actions: [
            IconButton(
              key: const ValueKey('production-pdf'),
              tooltip: l.pdf,
              icon: const Icon(AppIcons.pictureAsPdf),
              onPressed: _busy ? null : _pdf,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              children: [
                InfoItem(l.product, '${po.productCode} · ${po.productName}'),
                InfoItem(l.quantity, '${number(po.quantity)} ${po.unit}'),
                InfoItem(
                  l.order,
                  [
                    po.orderNumber,
                    po.customerName,
                  ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                ),
                InfoItem(l.priority, l.orderPriority(po.priority)),
                InfoItem(
                  l.productionBomRevision(po.bomRevision.toString()),
                  '',
                ),
                if (po.completedQuantity != null)
                  InfoItem(
                    l.productionQuantityBuilt,
                    '${number(po.completedQuantity)} ${po.unit}',
                  ),
              ],
            ),
            if (po.parentOrderId != null && po.parentOrderNumber != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('parent-order'),
                  icon: const Icon(AppIcons.subdirectoryArrowRight),
                  label: Text(l.productionSubassemblyOf(po.parentOrderNumber!)),
                  onPressed: () async {
                    await context.push('/production/${po.parentOrderId}');
                    _load();
                  },
                ),
              ),
            if ((po.productionRemark ?? '').isNotEmpty)
              Card(
                key: const ValueKey('production-remark'),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.productionRemark,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(po.productionRemark!),
                    ],
                  ),
                ),
              ),
            if (po.behindSchedule && po.scheduledEnd != null && open)
              Card(
                key: const ValueKey('behind-schedule'),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    l.productionBehindSchedule(date(po.scheduledEnd)),
                  ),
                ),
              ),
            if (po.orderCancelled && open)
              Card(
                key: const ValueKey('order-cancelled'),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l.productionOrderCancelled),
                ),
              ),
            if (canWrite) ...[
              gap,
              TutorialTarget(id: 'production-division', child: DropdownButtonFormField<String?>(
                key: ValueKey(
                  'division-${_division ?? ''}-${divisions.length}',
                ),
                initialValue: divisions.any((d) => d.id == _division)
                    ? _division
                    : null,
                decoration: InputDecoration(labelText: l.productionDivision),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l.productionNoDivision),
                  ),
                  // The order's own division stays visible when it was deactivated since, but
                  // cannot be chosen again once left.
                  for (final d in divisions.where(
                    (d) => d.active || d.id == po.divisionId,
                  ))
                    DropdownMenuItem(
                      value: d.id,
                      enabled: d.active,
                      child: Text(d.name),
                    ),
                ],
                onChanged: (v) => setState(() => _division = v),
              )),
              gap,
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('planned-ready'),
                    onPressed: _busy ? null : _pickReady,
                    icon: const Icon(AppIcons.calendarToday),
                    label: Text(
                      '${l.productionPlannedReady}: ${_ready == null ? '—' : date(_ready)}',
                    ),
                  ),
                  if (_ready != null)
                    IconButton(
                      tooltip: l.remove,
                      icon: const Icon(AppIcons.close),
                      onPressed: () => setState(() => _ready = null),
                    ),
                ],
              ),
              if (po.scheduledEnd != null &&
                  (_ready == null ||
                      _ready!.isBefore(dateOnly(po.scheduledEnd!))))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const ValueKey('use-scheduled-end'),
                    onPressed: () =>
                        setState(() => _ready = dateOnly(po.scheduledEnd!)),
                    child: Text(
                      l.productionUseScheduledEnd(date(po.scheduledEnd)),
                    ),
                  ),
                ),
              gap,
              TextField(
                controller: _notes,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(labelText: l.notes),
              ),
            ] else
              Wrap(
                children: [
                  InfoItem(l.productionDivision, po.divisionName ?? ''),
                  InfoItem(l.productionPlannedReady, date(po.plannedReadyDate)),
                  if (po.notes.isNotEmpty) InfoItem(l.notes, po.notes),
                ],
              ),
            gap,
            Text(
              l.productionComponents,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final c in po.components)
              ListTile(
                key: ValueKey('component-${c.id}'),
                contentPadding: EdgeInsets.zero,
                leading: c.short
                    ? Icon(
                        AppIcons.warningAmber,
                        color: Theme.of(context).colorScheme.error,
                      )
                    : null,
                title: Text('${c.componentCode} · ${c.componentName}'),
                subtitle: Text(
                  [
                    '${l.productionRequired} ${number(c.requiredQuantity)} ${c.unit}',
                    '${l.productionReserved} ${number(c.reservedQuantity)}',
                    if (po.status == 'completed')
                      '${l.productionConsumed} ${number(c.consumedQuantity)}',
                    if (po.status == 'completed' &&
                        (num.tryParse(c.scrapQuantity) ?? 0) > 0)
                      '${l.productionScrap} ${number(c.scrapQuantity)}',
                    if (c.short) l.productionShort,
                  ].join(' · '),
                ),
                trailing: canWrite && c.short && c.manufactured
                    ? TextButton(
                        key: ValueKey('build-${c.id}'),
                        onPressed: _busy ? null : () => _buildComponent(c),
                        child: Text(l.productionBuildComponent),
                      )
                    : null,
              ),
            OrderOperations(
              order: po,
              canRun: canRun,
              canWrite: canWrite,
              busy: _busy,
              run: (action) => _run(action),
            ),
            if (po.subOrders.isNotEmpty) ...[
              gap,
              Text(
                l.productionSubOrders,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final c in po.subOrders)
                ListTile(
                  key: ValueKey('sub-order-${c.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${c.number} · ${c.productCode} · ${number(c.quantity)} ${c.unit}',
                  ),
                  subtitle: Text(
                    [
                      l.productionStatus(c.status),
                      if (c.scheduledEnd != null) date(c.scheduledEnd),
                    ].join(' · '),
                  ),
                  trailing: const Icon(AppIcons.chevronRight),
                  onTap: () async {
                    await context.push('/production/${c.id}');
                    _load();
                  },
                ),
            ],
            if (po.plannedCost != null) ...[
              gap,
              Text(
                l.productionCost,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _costRow(l, l.productionCostPlanned, po.plannedCost!),
              if (po.actualCost != null)
                _costRow(l, l.productionCostActual, po.actualCost!),
              if (po.plannedCost!.incomplete)
                Text(
                  l.productionCostIncomplete,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (po.outputs.isNotEmpty) ...[
              gap,
              Text(
                l.productionOutput,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final o in po.outputs)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    o.serialNumber ??
                        o.lotNumber ??
                        '${number(o.quantity)} ${po.unit}',
                  ),
                  subtitle: Text('${number(o.quantity)} ${po.unit}'),
                ),
            ],
            gap,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canWrite)
                  TutorialTarget(id: 'production-save', child: OutlinedButton(
                    key: const ValueKey('save-production'),
                    onPressed: _busy ? null : _save,
                    child: Text(l.save),
                  )),
                if (canWrite && anyShort)
                  OutlinedButton(
                    key: const ValueKey('reserve-again'),
                    onPressed: _busy
                        ? null
                        : () =>
                              _run(() => _api.reserveComponents(id: widget.id)),
                    child: Text(l.productionReserveAgain),
                  ),
                if (canRun && po.status == 'released')
                  TutorialTarget(id: 'production-start', child: OutlinedButton.icon(
                    key: const ValueKey('start-production'),
                    onPressed: _busy
                        ? null
                        : () => _run(() => _api.startOrder(id: widget.id)),
                    icon: const Icon(AppIcons.playArrow),
                    label: Text(l.productionStart),
                  )),
                if (canRun && !po.orderCancelled)
                  TutorialTarget(id: 'production-complete', child: FilledButton.icon(
                    key: const ValueKey('complete-production'),
                    onPressed: _busy ? null : _complete,
                    icon: const Icon(AppIcons.check),
                    label: Text(l.productionComplete),
                  )),
                if (canWrite)
                  TextButton(
                    key: const ValueKey('cancel-production'),
                    onPressed: _busy ? null : _cancel,
                    child: Text(l.productionCancel),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of cost: what it is, material and labour, and the total.
Widget _costRow(AppLocalizations l, String label, ProductionOrderCost c) =>
    ListTile(
      key: ValueKey('cost-$label'),
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(
        '${l.productionCostMaterial} ${money(c.materialCost)} · ${l.productionCostLabour} ${money(c.labourCost)}',
      ),
      trailing: Text(money(c.totalCost)),
    );
