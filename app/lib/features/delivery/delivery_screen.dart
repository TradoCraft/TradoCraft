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

/// A line of the note being edited: what is picked, from where, and which serial number.
class _Pick {
  _Pick(this.line)
    : quantity = line.quantity,
      serialUnitId = line.serialUnitId,
      serialNumber = line.serialNumber;
  final DeliveryNoteLine line;
  String quantity;
  String? serialUnitId;
  String? serialNumber;
}

/// One delivery note: planned date (checked against the customer's closures, following the
/// company's policy), carrier, address, picking list, shipping, cancelling and the PDF.
class DeliveryScreen extends ConsumerStatefulWidget {
  const DeliveryScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends ConsumerState<DeliveryScreen> {
  DeliveryNote? _note;
  String _policy = 'warn';
  String? _error;
  bool _busy = false;

  DateTime? _date;
  DeliveryCheck? _check;
  int _checkRequest = 0;
  List<_Pick> _picks = [];
  final _carrier = TextEditingController();
  final _tracking = TextEditingController();
  final _notes = TextEditingController();
  final _reason = TextEditingController();
  final _toName = TextEditingController();
  final _toStreet = TextEditingController();
  final _toPostal = TextEditingController();
  final _toCity = TextEditingController();
  final _toCountry = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [
      _carrier,
      _tracking,
      _notes,
      _reason,
      _toName,
      _toStreet,
      _toPostal,
      _toCity,
      _toCountry,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Set<String> get _perms =>
      ref.read(meProvider).value?.permissions.toSet() ?? const {};

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    try {
      final note = await api.delivery.getNote(id: widget.id);
      final settings = await api.delivery.getSettings();
      if (!mounted) return;
      _fill(note);
      setState(() {
        _policy = settings.closurePolicy;
        _error = null;
      });
      await _checkDate(_date);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _fill(DeliveryNote n) {
    _note = n;
    _date = n.plannedDate == null ? null : dateOnly(n.plannedDate!);
    _picks = [for (final l in n.lines) _Pick(l)];
    _carrier.text = n.carrier;
    _tracking.text = n.trackingNumber;
    _notes.text = n.notes;
    _reason.text = n.closureOverrideReason ?? '';
    _toName.text = n.shipTo.name;
    _toStreet.text = n.shipTo.street;
    _toPostal.text = n.shipTo.postalCode;
    _toCity.text = n.shipTo.city;
    _toCountry.text = n.shipTo.countryCode;
  }

  /// Asks the API whether the customer is closed on [d]. Reading closures needs
  /// `customers.read`; without it the warning that came with the note is used for the saved date,
  /// and the server still applies the policy when saving. Only the latest call may set the result.
  Future<void> _checkDate(DateTime? d) async {
    final request = ++_checkRequest;
    final note = _note;
    DeliveryCheck? check;
    if (d != null && note != null && note.status == 'planned') {
      try {
        check = await ref
            .read(apiProvider)
            .crm
            .checkDeliveryDay(id: note.customerId, date: d);
      } catch (_) {
        final saved = note.closureWarning;
        final savedDate = note.plannedDate == null
            ? null
            : dateOnly(note.plannedDate!);
        if (saved != null && savedDate == d) {
          check = DeliveryCheck(
            date: d,
            closed: true,
            closure: saved.closure,
            nextOpenDay: saved.nextOpenDay,
          );
        }
      }
    }
    if (mounted && request == _checkRequest) setState(() => _check = check);
  }

  bool get _dateChanged {
    final n = _note!;
    final saved = n.plannedDate == null ? null : dateOnly(n.plannedDate!);
    return _date != saved;
  }

  bool get _closed => _check?.closed ?? false;

  /// Saving is held back while the policy refuses what is entered; the server decides in the end.
  bool get _saveBlocked {
    if (!_closed || !_dateChanged) return false;
    if (_policy == 'block') return true;
    if (_policy == 'override') {
      return _reason.text.trim().isEmpty ||
          !_perms.contains('delivery.override_closure');
    }
    return false;
  }

  Future<void> _pickDate() async {
    final now = dateOnly(DateTime.now());
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: _date != null && _date!.isBefore(now) ? _date! : now,
      lastDate: _date != null && _date!.isAfter(DateTime(now.year + 3))
          ? _date!
          : DateTime(now.year + 3),
    );
    if (d == null) return;
    setState(() => _date = dateOnly(d));
    await _checkDate(_date);
  }

  Future<void> _useDate(DateTime d) async {
    setState(() => _date = dateOnly(d));
    await _checkDate(_date);
  }

  UpdateDeliveryInput _input() => UpdateDeliveryInput(
    plannedDate: _date,
    carrier: _carrier.text.trim(),
    trackingNumber: _tracking.text.trim(),
    notes: _notes.text.trim(),
    closureOverrideReason: _reason.text.trim().isEmpty
        ? null
        : _reason.text.trim(),
    expectedUpdatedAt: _note!.updatedAt,
    shipTo: DeliveryShipToInput(
      name: _toName.text.trim(),
      street: _toStreet.text.trim(),
      postalCode: _toPostal.text.trim(),
      city: _toCity.text.trim(),
      countryCode: _toCountry.text.trim(),
    ),
    lines: [
      for (final p in _picks)
        DeliveryLineInput(
          orderLineId: p.line.orderLineId,
          quantity: parseDecimalInput(p.quantity) ?? p.quantity,
          locationId: p.line.locationId,
          lotId: p.line.lotId,
          serialUnitId: p.serialUnitId,
        ),
    ],
  );

  Future<bool> _save({String? success}) async {
    var ok = false;
    await _run(() async {
      final saved = await ref
          .read(apiProvider)
          .delivery
          .updateNote(id: widget.id, body: _input());
      _fill(saved);
      ok = true;
      if (success != null && mounted) _snack(success);
    });
    if (ok) await _checkDate(_date);
    return ok;
  }

  Future<void> _ship() async {
    final l = context.l10n;
    if (_perms.contains('delivery.write') && !await _save()) return;
    await _run(() async {
      final shipped = await ref
          .read(apiProvider)
          .delivery
          .shipNote(
            id: widget.id,
            body: ShipDeliveryInput(
              carrier: _carrier.text.trim(),
              trackingNumber: _tracking.text.trim(),
            ),
          );
      _fill(shipped);
      _check = null;
      if (mounted) _snack(l.deliveryShippedSnack);
    });
  }

  Future<void> _cancel() async {
    final l = context.l10n;
    final reason = await askText(
      context,
      title: l.deliveryCancel,
      label: l.deliveryCancelReason,
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _run(() async {
      final cancelled = await ref
          .read(apiProvider)
          .delivery
          .cancelNote(
            id: widget.id,
            body: CancelDeliveryInput(reason: reason.trim()),
          );
      _fill(cancelled);
      _check = null;
    });
  }

  Future<void> _pdf() => _run(() async {
    final n = _note!;
    final bytes = await downloadBytes(
      ref.read(dioProvider),
      '/api/v1/deliveries/${n.id}/pdf',
    );
    await Printing.layoutPdf(
      name: '${n.number}.pdf',
      onLayout: (_) async => Uint8List.fromList(bytes),
    );
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
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

  Future<void> _chooseSerial(_Pick p) async {
    final unit = await showDialog<SerialChoice>(
      context: context,
      builder: (_) => _SerialPicker(noteId: widget.id, lineId: p.line.id),
    );
    if (unit != null) {
      setState(() {
        p.serialUnitId = unit.id;
        p.serialNumber = unit.serialNumber;
      });
    }
  }

  Future<void> _editQuantity(_Pick p) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _QuantityDialog(initial: p.quantity),
    );
    final parsed = value == null ? null : parseDecimalInput(value);
    if (parsed != null) setState(() => p.quantity = parsed);
  }

  Widget _closureBanner(DeliveryNote n) {
    final l = context.l10n;
    final c = _check;
    if (!_closed || c == null || c.closure == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final canOverride = _perms.contains('delivery.override_closure');
    return Card(
      key: const ValueKey('closure-banner'),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.eventBusy, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.deliveryClosedWarning(
                      date(c.closure!.startsOn),
                      date(c.closure!.endsOn),
                      date(c.nextOpenDay),
                    ),
                  ),
                ),
              ],
            ),
            if (_dateChanged && _policy == 'block') ...[
              const SizedBox(height: 8),
              Text(l.deliveryBlocked),
            ],
            if (_dateChanged && _policy == 'override') ...[
              const SizedBox(height: 8),
              if (!canOverride) Text(l.deliveryOverrideNeedsRight),
              TextField(
                key: const ValueKey('override-reason'),
                controller: _reason,
                enabled: canOverride,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.deliveryOverrideReason,
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('use-next-open-day'),
                onPressed: () => _useDate(c.nextOpenDay),
                child: Text(l.deliveryUseDay(date(c.nextOpenDay))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lines(DeliveryNote n, bool editable) {
    final l = context.l10n;
    if (_picks.isEmpty) return Text(l.deliveryNoLines);
    return Column(
      children: [
        for (final p in _picks)
          ListTile(
            key: ValueKey('line-${p.line.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${p.line.orderPosition} · ${p.line.productCode} ${p.line.productName}',
            ),
            subtitle: Text(
              [
                '${number(p.quantity)} ${p.line.unit}',
                '${l.deliveryLocation} ${p.line.location}',
                if (p.line.lotNumber != null)
                  '${l.deliveryLot} ${p.line.lotNumber}',
                if (p.serialNumber != null)
                  '${l.deliverySerial} ${p.serialNumber}',
              ].join(' · '),
            ),
            trailing: !editable
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (p.line.tracking == 'serial')
                        TextButton(
                          key: ValueKey('serial-${p.line.id}'),
                          onPressed: () => _chooseSerial(p),
                          child: Text(p.serialNumber ?? l.deliveryChooseSerial),
                        )
                      else
                        IconButton(
                          tooltip: l.quantity,
                          icon: const Icon(AppIcons.edit),
                          onPressed: () => _editQuantity(p),
                        ),
                      IconButton(
                        key: ValueKey('remove-${p.line.id}'),
                        tooltip: l.remove,
                        icon: const Icon(AppIcons.delete),
                        onPressed: () => setState(() => _picks.remove(p)),
                      ),
                    ],
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final n = _note;
    if (n == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l.deliveries)),
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
    // Watched, so the screen rebuilds when the user's rights arrive.
    final perms = ref.watch(meProvider).value?.permissions.toSet() ?? const {};
    final planned = n.status == 'planned';
    final canWrite = planned && perms.contains('delivery.write');
    final canShip = planned && perms.contains('delivery.ship');
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text('${n.number} · ${l.deliveryStatus(n.status)}'),
        actions: [
          IconButton(
            key: const ValueKey('delivery-pdf'),
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
              InfoItem(l.customer, n.customerName),
              InkWell(
                onTap: () => context.push('/orders/${n.orderId}'),
                child: InfoItem(l.order, n.orderNumber),
              ),
              InfoItem(
                l.deliveryPlannedDate,
                n.plannedDate == null ? '' : date(n.plannedDate),
              ),
              if (n.shippedAt != null)
                InfoItem(l.deliveryStatusShipped, date(n.shippedAt)),
            ],
          ),
          if (planned) _closureBanner(n),
          if (canWrite) ...[
            gap,
            Row(
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('planned-date'),
                  onPressed: _busy ? null : _pickDate,
                  icon: const Icon(AppIcons.calendarToday),
                  label: Text(
                    '${l.deliveryPlannedDate}: ${_date == null ? l.deliveryNoDate : date(_date)}',
                  ),
                ),
                if (_date != null)
                  IconButton(
                    tooltip: l.remove,
                    icon: const Icon(AppIcons.close),
                    onPressed: () async {
                      setState(() => _date = null);
                      await _checkDate(null);
                    },
                  ),
              ],
            ),
            gap,
            TextField(
              key: const ValueKey('carrier'),
              controller: _carrier,
              decoration: InputDecoration(labelText: l.carrier),
            ),
            gap,
            TextField(
              key: const ValueKey('tracking'),
              controller: _tracking,
              decoration: InputDecoration(labelText: l.trackingNumber),
            ),
            gap,
            Text(
              l.deliveryShipTo,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            TextField(
              controller: _toName,
              decoration: InputDecoration(labelText: l.name),
            ),
            TextField(
              controller: _toStreet,
              decoration: InputDecoration(labelText: l.street),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _toPostal,
                    decoration: InputDecoration(labelText: l.postalCode),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _toCity,
                    decoration: InputDecoration(labelText: l.city),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _toCountry,
                    decoration: InputDecoration(labelText: l.country),
                  ),
                ),
              ],
            ),
            TextField(
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(labelText: l.notes),
            ),
          ] else ...[
            Wrap(
              children: [
                InfoItem(l.carrier, n.carrier),
                InfoItem(l.trackingNumber, n.trackingNumber),
                InfoItem(
                  l.deliveryShipTo,
                  [
                    n.shipTo.name,
                    n.shipTo.street,
                    '${n.shipTo.postalCode} ${n.shipTo.city}'.trim(),
                  ].where((s) => s.isNotEmpty).join(', '),
                ),
                if (n.notes.isNotEmpty) InfoItem(l.notes, n.notes),
              ],
            ),
          ],
          gap,
          Text(
            l.deliveryPicking,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          _lines(n, canWrite),
          gap,
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canWrite)
                OutlinedButton(
                  key: const ValueKey('save-delivery'),
                  onPressed: _busy || _saveBlocked
                      ? null
                      : () => _save(success: l.saved),
                  child: Text(l.save),
                ),
              if (canShip)
                FilledButton.icon(
                  key: const ValueKey('ship-delivery'),
                  onPressed: _busy || _saveBlocked || _picks.isEmpty
                      ? null
                      : _ship,
                  icon: const Icon(AppIcons.outbox),
                  label: Text(l.deliveryShip),
                ),
              if (canWrite)
                TextButton(
                  key: const ValueKey('cancel-delivery'),
                  onPressed: _busy ? null : _cancel,
                  child: Text(l.deliveryCancel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for a quantity. Owns its controller, so it is disposed with the dialog and not before.
class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.initial});
  final String initial;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.quantity),
      content: TextField(
        key: const ValueKey('line-quantity'),
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(l.save),
        ),
      ],
    );
  }
}

/// Picks a serial number among the units that are in stock at the location of the pick.
class _SerialPicker extends ConsumerStatefulWidget {
  const _SerialPicker({required this.noteId, required this.lineId});
  final String noteId;
  final String lineId;

  @override
  ConsumerState<_SerialPicker> createState() => _SerialPickerState();
}

class _SerialPickerState extends ConsumerState<_SerialPicker> {
  List<SerialChoice>? _units;
  String? _error;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final units = await ref
          .read(apiProvider)
          .delivery
          .serialChoices(
            id: widget.noteId,
            lineId: widget.lineId,
            q: _q.text.trim().isEmpty ? null : _q.text.trim(),
          );
      if (mounted) {
        setState(() {
          _units = units;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final units = _units;
    return AlertDialog(
      title: Text(l.deliveryChooseSerial),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('serial-search'),
              controller: _q,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: l.search,
                suffixIcon: IconButton(
                  icon: const Icon(AppIcons.search),
                  onPressed: _load,
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Text(_error!)
            else if (units == null)
              const LinearProgressIndicator()
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final u in units)
                      ListTile(
                        key: ValueKey('unit-${u.id}'),
                        title: Text(u.serialNumber),
                        onTap: () => Navigator.pop(context, u),
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
