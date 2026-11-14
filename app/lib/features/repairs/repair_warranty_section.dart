import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart' as fmt;

/// The warranty card of a repair: the automatic result from the serial unit (compared with the
/// arrival date), the final status, and the workshop's override to "void (misuse)". The override
/// needs `repairs.warranty_void` and a reason; the automatic result always stays visible.
class RepairWarrantySection extends ConsumerStatefulWidget {
  const RepairWarrantySection({
    super.key,
    required this.repair,
    required this.open,
    required this.onChanged,
  });
  final Repair repair;

  /// False for shipped and cancelled repairs: nothing can change any more.
  final bool open;

  /// Called with the repair after a change, so the screen shows the new final status and history.
  final void Function(RepairDetail) onChanged;

  @override
  ConsumerState<RepairWarrantySection> createState() =>
      _RepairWarrantySectionState();
}

class _RepairWarrantySectionState extends ConsumerState<RepairWarrantySection> {
  RepairWarranty? _w;
  String? _error;
  bool _busy = false;

  RepairsClient get _api => ref.read(apiProvider).repairs;
  String get _id => widget.repair.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didUpdateWidget(RepairWarrantySection old) {
    super.didUpdateWidget(old);
    if (old.repair.warranty != widget.repair.warranty ||
        old.repair.serialUnitId != widget.repair.serialUnitId ||
        old.repair.status != widget.repair.status) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final w = await _api.getRepairWarranty(id: _id);
      if (mounted) {
        setState(() {
          _w = w;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  Future<void> _detail(Future<RepairDetail> Function() action) async {
    setState(() => _busy = true);
    RepairDetail? d;
    final ok = await runAction(
      context,
      () async => d = await action(),
      success: context.l10n.saved,
    );
    if (mounted) setState(() => _busy = false);
    if (ok && d != null) {
      widget.onChanged(d!);
      await _load();
    }
  }

  Future<void> _recheck() async {
    setState(() => _busy = true);
    RepairWarranty? w;
    final ok = await runAction(
      context,
      () async => w = await _api.recheckRepairWarranty(id: _id),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _w = w;
    });
    if (ok) {
      final d = await _api.getRepair(id: _id);
      if (mounted) widget.onChanged(d);
    }
  }

  Future<void> _void() async {
    final l = context.l10n;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) =>
          ReasonDialog(title: l.warrantyVoidTitle, confirm: l.markWarrantyVoid),
    );
    if (reason == null || !mounted) return;
    await _detail(
      () => _api.voidRepairWarranty(
        id: _id,
        body: WarrantyOverrideInput(reason: reason),
      ),
    );
  }

  Future<void> _removeOverride() async {
    final l = context.l10n;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: l.warrantyRemoveTitle,
        confirm: l.removeWarrantyOverride,
      ),
    );
    if (reason == null || !mounted) return;
    await _detail(
      () => _api.removeRepairWarrantyOverride(
        id: _id,
        body: WarrantyOverrideInput(reason: reason),
      ),
    );
  }

  Future<void> _linkUnit(RepairWarranty w) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) =>
          SerialUnitDialog(repair: widget.repair, candidates: w.candidates),
    );
    if (picked == null || !mounted) return;
    await _detail(
      () => _api.setRepairSerialUnit(
        id: _id,
        body: SerialUnitInput(serialUnitId: picked),
      ),
    );
  }

  Future<void> _unlinkUnit() => _detail(
    () => _api.setRepairSerialUnit(
      id: _id,
      body: const SerialUnitInput(clear: true),
    ),
  );

  Widget _badge(BuildContext context, String status) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      'in_warranty' => (AppIcons.verified, Colors.green.shade700),
      'out_of_warranty' => (AppIcons.cancel, scheme.onSurfaceVariant),
      'void' => (AppIcons.gppBad, scheme.error),
      _ => (AppIcons.help, scheme.onSurfaceVariant),
    };
    return Chip(
      key: const ValueKey('warranty-final'),
      avatar: Icon(icon, size: 18, color: color),
      label: Text(l.warrantyLabel(status)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final w = _w;
    final canVoid = can(ref, 'repairs.warranty_void') && widget.open;
    final canIntake = can(ref, 'repairs.intake') && widget.open;
    final canRecheck = can(ref, 'repairs.write') && widget.open;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(l.warrantySection, style: theme.textTheme.titleSmall),
            const SizedBox(width: 12),
            _badge(context, w?.warranty ?? widget.repair.warranty),
            const Spacer(),
            if (canRecheck)
              IconButton(
                tooltip: l.recheckWarranty,
                icon: const Icon(AppIcons.refresh),
                onPressed: _busy ? null : _recheck,
              ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error))
        else if (w == null)
          const LinearProgressIndicator()
        else ...[
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${l.warrantyAutomatic}: ${l.warrantyLabel(w.auto)}'
              '${w.autoUntil == null ? '' : ' (${l.warrantyUntilDate(fmt.date(w.autoUntil))})'}',
              key: const ValueKey('warranty-auto'),
            ),
          ),
          Text(
            l.warrantyComparedWith(fmt.date(w.comparedWith)),
            style: theme.textTheme.bodySmall,
          ),
          if (!w.arrived)
            Text(l.warrantyProvisional, style: theme.textTheme.bodySmall),
          Row(
            children: [
              Expanded(
                child: Text(
                  w.serialUnit == null
                      ? l.noSerialUnit
                      : l.serialUnitLabel(
                          '${w.serialUnit!.productCode} · ${w.serialUnit!.serialNumber}',
                        ),
                  key: const ValueKey('warranty-unit'),
                ),
              ),
              if (canIntake && w.serialUnit != null)
                IconButton(
                  tooltip: l.unlinkSerialUnit,
                  icon: const Icon(AppIcons.linkOff),
                  onPressed: _busy ? null : _unlinkUnit,
                ),
              if (canIntake && w.serialUnit == null)
                TextButton.icon(
                  onPressed: _busy ? null : () => _linkUnit(w),
                  icon: const Icon(AppIcons.link, size: 18),
                  label: Text(l.linkSerialUnit),
                ),
            ],
          ),
          if (w.serialUnit == null && w.candidates.length > 1)
            Text(
              l.serialUnitSeveral,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          if (w.overridden) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('warranty-override'),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                l.warrantyOverriddenBy(
                  w.overrideByName ?? '',
                  w.overrideAt == null ? '' : fmt.date(w.overrideAt!.toLocal()),
                  w.overrideReason,
                ),
              ),
            ),
          ],
          if (canVoid)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: w.overridden
                    ? OutlinedButton.icon(
                        onPressed: _busy ? null : _removeOverride,
                        icon: const Icon(AppIcons.undo, size: 18),
                        label: Text(l.removeWarrantyOverride),
                      )
                    : OutlinedButton.icon(
                        onPressed: _busy ? null : _void,
                        icon: const Icon(AppIcons.gppBad, size: 18),
                        label: Text(l.markWarrantyVoid),
                      ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Asks for a mandatory reason; the confirm button stays disabled while the text is blank.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({super.key, required this.title, required this.confirm});
  final String title;
  final String confirm;

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 440,
        child: TextField(
          controller: _reason,
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: l.warrantyReasonLabel),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _reason.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, _reason.text.trim()),
          child: Text(widget.confirm),
        ),
      ],
    );
  }
}

/// Picks the serial unit of a repair: the candidates that match its serial number first, and a
/// search over all serial units (of the repair's product when it has one).
class SerialUnitDialog extends ConsumerStatefulWidget {
  const SerialUnitDialog({
    super.key,
    required this.repair,
    required this.candidates,
  });
  final Repair repair;
  final List<SerialUnitRef> candidates;

  @override
  ConsumerState<SerialUnitDialog> createState() => _SerialUnitDialogState();
}

class _SerialUnitDialogState extends ConsumerState<SerialUnitDialog> {
  late final _q = TextEditingController(text: widget.repair.serialNumber);
  List<({String id, String label})>? _results;
  String? _error;

  @override
  void initState() {
    super.initState();
    _results = [
      for (final c in widget.candidates)
        (id: c.id, label: '${c.productCode} · ${c.serialNumber}'),
    ];
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    try {
      final page = await ref
          .read(apiProvider)
          .engineering
          .listSerials(
            q: _q.text.trim(),
            productId: widget.repair.productId,
            limit: 20,
          );
      if (mounted) {
        setState(() {
          _error = null;
          _results = [
            for (final s in page.items)
              (id: s.id, label: '${s.productCode} · ${s.serialNumber}'),
          ];
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final results = _results ?? const [];
    return AlertDialog(
      title: Text(l.linkSerialUnit),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.candidates.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(l.serialUnitSeveral),
              ),
            TextField(
              controller: _q,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                labelText: l.serialNumber,
                suffixIcon: IconButton(
                  tooltip: l.search,
                  icon: const Icon(AppIcons.search),
                  onPressed: _search,
                ),
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (results.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(l.serialUnitNoResults),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in results)
                    ListTile(
                      key: ValueKey('unit-${r.id}'),
                      dense: true,
                      title: Text(r.label),
                      onTap: () => Navigator.pop(context, r.id),
                    ),
                ],
              ),
            ),
          ],
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
