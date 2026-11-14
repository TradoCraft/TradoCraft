import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/auth_image.dart';
import '../../shared/format.dart';
import '../../shared/photos.dart' show newClientId;
import '../../shared/search_picker.dart';
import 'offline/offline_queue.dart';
import 'offline/offline_ui.dart' show showQueuedSnack;
import 'signature_dialog.dart';
import '../../shared/app_icons.dart';

/// A chip saying whether a unit is in warranty.
class WarrantyChip extends StatelessWidget {
  const WarrantyChip({super.key, required this.status, this.until});
  final String status;
  final DateTime? until;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      'in_warranty' => (l.warrantyIn, scheme.primaryContainer),
      'expired' => (l.warrantyExpired, scheme.errorContainer),
      _ => (l.warrantyUnknown, scheme.surfaceContainerHighest),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color,
      label: Text(
        until != null && status != 'unknown'
            ? '$label · ${l.warrantyUntilDate(date(until))}'
            : label,
      ),
    );
  }
}

/// Parts, equipment, signature and service report of a job.
class JobExtras extends ConsumerWidget {
  const JobExtras({
    super.key,
    required this.detail,
    required this.canWork,
    required this.planner,
    required this.onChanged,
    this.pending = const {},
  });

  final JobDetail detail;
  final bool canWork;
  final bool planner;

  /// Ids of records whose change is still waiting in the offline queue.
  final Set<String> pending;
  final ValueChanged<JobDetail> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final j = detail.job;
    final field = ref.read(apiProvider).field;
    final open = j.status == 'planned' || j.status == 'in_progress';
    // Open jobs can be changed by whoever works on them; completed ones only by planners.
    final canEdit = canWork && (open || (planner && j.status == 'completed'));
    final canSign =
        canWork &&
        (j.status == 'in_progress' || j.status == 'completed') &&
        j.reportSentAt == null;
    final sig = detail.signature;

    Future<void> run(Future<JobDetail> Function() action) async {
      JobDetail? d;
      final ok = await runAction(context, () async => d = await action());
      if (ok && d != null) onChanged(d!);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Parts used
        Row(
          children: [
            Text(l.partsUsed, style: theme.textTheme.titleSmall),
            const Spacer(),
            if (canEdit)
              TextButton.icon(
                icon: const Icon(AppIcons.add),
                label: Text(l.addPart),
                onPressed: () async {
                  final d = await showDialog<JobDetail>(
                    context: context,
                    builder: (_) => PartDialog(
                      jobId: j.id,
                      jobLabel: '${j.number} ${j.title}',
                    ),
                  );
                  if (d != null) onChanged(d);
                },
              ),
          ],
        ),
        if (detail.parts.isEmpty)
          Text(l.noParts, style: theme.textTheme.bodySmall),
        for (final p in detail.parts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.inventory2, size: 20),
            title: Text('${number(p.quantity)} ${p.unit} · ${p.description}'),
            subtitle: Text(
              [
                if (p.productCode != null) p.productCode!,
                if (p.serialNumber != null) p.serialNumber!,
                if (!p.billable) '—',
                if (p.addedByName != null) p.addedByName!,
              ].join(' · '),
            ),
            trailing: pending.contains(p.id)
                ? Tooltip(
                    message: l.offlinePendingSync,
                    child: const Icon(AppIcons.cloudUpload, size: 18),
                  )
                : canEdit
                ? IconButton(
                    tooltip: l.remove,
                    icon: const Icon(AppIcons.delete),
                    onPressed: () =>
                        run(() => field.removeJobPart(id: j.id, partId: p.id)),
                  )
                : null,
          ),
        const Divider(height: 32),
        // Equipment
        Row(
          children: [
            Text(l.equipment, style: theme.textTheme.titleSmall),
            const Spacer(),
            if (canEdit)
              TextButton.icon(
                icon: const Icon(AppIcons.add),
                label: Text(l.addEquipment),
                onPressed: () async {
                  final d = await showDialog<JobDetail>(
                    context: context,
                    builder: (_) => EquipmentPicker(detail: detail),
                  );
                  if (d != null) onChanged(d);
                },
              ),
          ],
        ),
        if (detail.equipment.isEmpty)
          Text(l.noEquipment, style: theme.textTheme.bodySmall),
        for (final e in detail.equipment)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(AppIcons.precisionManufacturing),
            title: Text('${e.productCode} · ${e.productName}'),
            subtitle: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                Text(e.serialNumber),
                WarrantyChip(status: e.warrantyStatus, until: e.warrantyUntil),
              ],
            ),
            trailing: canEdit
                ? IconButton(
                    tooltip: l.remove,
                    icon: const Icon(AppIcons.linkOff),
                    onPressed: () => run(
                      () => field.removeJobEquipment(
                        id: j.id,
                        serialUnitId: e.serialUnitId,
                      ),
                    ),
                  )
                : null,
          ),
        const Divider(height: 32),
        // Signature
        Row(
          children: [
            Text(l.customerSignature, style: theme.textTheme.titleSmall),
            const Spacer(),
            if (canSign)
              TextButton.icon(
                icon: const Icon(AppIcons.draw),
                label: Text(
                  sig == null ? l.captureSignature : l.replaceSignature,
                ),
                onPressed: () async {
                  final d = await showSignatureDialog(context, detail);
                  if (d != null) onChanged(d);
                },
              ),
          ],
        ),
        if (sig == null)
          Text(l.noSignature, style: theme.textTheme.bodySmall)
        else if (sig.declined)
          Text(l.declinedToSignWithReason(sig.declineReason))
        else ...[
          Text(l.signedByOn(sig.signerName, date(sig.signedAt.toLocal()))),
          if (sig.hasImage)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Container(
                color: Colors.white,
                child: AuthImage(
                  dio: ref.watch(dioProvider),
                  path:
                      '/api/v1/field/jobs/${j.id}/signature?v=${sig.signedAt.millisecondsSinceEpoch}',
                  maxHeight: 120,
                ),
              ),
            ),
        ],
        const Divider(height: 32),
        // Service report
        Text(l.serviceReport, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              icon: const Icon(AppIcons.pictureAsPdf),
              label: Text(l.reportView),
              onPressed: () => runAction(context, () async {
                final bytes = await downloadBytes(
                  ref.read(dioProvider),
                  '/api/v1/field/jobs/${j.id}/report',
                );
                await Printing.layoutPdf(
                  name: '${j.number}-service-report.pdf',
                  onLayout: (_) async => Uint8List.fromList(bytes),
                );
              }),
            ),
            if (canWork && j.status == 'completed')
              FilledButton.icon(
                icon: const Icon(AppIcons.mail),
                label: Text(l.reportSend),
                onPressed: () async {
                  JobDetail? d;
                  final ok = await runAction(
                    context,
                    () async => d = await field.sendJobReport(id: j.id),
                    success: l.reportQueued,
                  );
                  if (ok && d != null) onChanged(d!);
                },
              ),
          ],
        ),
        if (j.reportSentAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.reportSentTo(j.reportSentTo, date(j.reportSentAt!.toLocal())),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Adds a part: a product from the catalogue or free text. The entry gets its id when the dialog
/// opens, so pressing Save again after a failed attempt cannot record it twice.
class PartDialog extends ConsumerStatefulWidget {
  const PartDialog({super.key, required this.jobId, this.jobLabel = ''});
  final String jobId;
  final String jobLabel;

  @override
  ConsumerState<PartDialog> createState() => _PartDialogState();
}

class _PartDialogState extends ConsumerState<PartDialog> {
  final _id = newClientId();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unit = TextEditingController(text: 'pcs');
  Product? _product;
  bool _billable = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _description.dispose();
    _quantity.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final quantity = parseDecimalInput(_quantity.text);
    if (quantity == null || _description.text.trim().isEmpty) {
      setState(() => _error = context.l10n.partFreeTextHint);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final description = _description.text.trim();
      final unit = _unit.text.trim();
      final d = await submitWrite(
        ref.read(offlineQueueProvider),
        type: OpType.partAdd,
        jobId: widget.jobId,
        jobLabel: widget.jobLabel,
        id: _id,
        payload: {
          'product_id': _product?.id,
          'description': description,
          'quantity': quantity,
          'unit': unit,
          'billable': _billable,
        },
        online: () => ref
            .read(apiProvider)
            .field
            .addJobPart(
              id: widget.jobId,
              body: PartInput(
                id: _id,
                productId: _product?.id,
                description: description,
                quantity: quantity,
                unit: unit,
                billable: _billable,
              ),
            ),
      );
      if (!mounted) return;
      if (d == null) showQueuedSnack(context);
      Navigator.pop(context, d);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.addPart),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SearchPicker<Product>(
                label: l.product,
                display: (p) => '${p.code} · ${p.name}',
                search: (q) async =>
                    (await ref
                            .read(apiProvider)
                            .products
                            .listProducts(q: q, limit: 20))
                        .items,
                onSelected: (p) => setState(() {
                  _product = p;
                  _description.text = p.name;
                  _unit.text = p.unit;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: InputDecoration(labelText: l.description),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantity,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(labelText: l.quantity),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _unit,
                      decoration: InputDecoration(labelText: l.unit),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.billable),
                value: _billable,
                onChanged: (v) => setState(() => _billable = v),
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l.save)),
      ],
    );
  }
}

/// Picks a unit of the job's customer to link to the job.
class EquipmentPicker extends ConsumerStatefulWidget {
  const EquipmentPicker({super.key, required this.detail});
  final JobDetail detail;

  @override
  ConsumerState<EquipmentPicker> createState() => _EquipmentPickerState();
}

class _EquipmentPickerState extends ConsumerState<EquipmentPicker> {
  late final Future<List<CustomerEquipment>> _units = ref
      .read(apiProvider)
      .field
      .listCustomerEquipment(id: widget.detail.job.customerId);
  String? _error;

  Future<void> _pick(CustomerEquipment u) async {
    try {
      final d = await ref
          .read(apiProvider)
          .field
          .addJobEquipment(
            id: widget.detail.job.id,
            body: EquipmentInput(serialUnitId: u.serialUnitId),
          );
      if (mounted) Navigator.pop(context, d);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final linked = widget.detail.equipment.map((e) => e.serialUnitId).toSet();
    return AlertDialog(
      title: Text(l.addEquipment),
      content: SizedBox(
        width: 460,
        child: FutureBuilder<List<CustomerEquipment>>(
          future: _units,
          builder: (context, s) {
            if (s.hasError) return Text(errorMessage(s.error!));
            if (!s.hasData) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final units = s.data!
                .where((u) => !linked.contains(u.serialUnitId))
                .toList();
            if (units.isEmpty) return Text(l.noCustomerEquipment);
            return ListView(
              shrinkWrap: true,
              children: [
                for (final u in units)
                  ListTile(
                    title: Text('${u.productCode} · ${u.productName}'),
                    subtitle: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(u.serialNumber),
                        WarrantyChip(
                          status: u.warrantyStatus,
                          until: u.warrantyUntil,
                        ),
                      ],
                    ),
                    onTap: () => _pick(u),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
      ],
    );
  }
}
