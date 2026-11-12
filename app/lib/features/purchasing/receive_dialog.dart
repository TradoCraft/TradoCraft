import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../inventory/inventory_common.dart';
import '../tutorial/targets.dart';

/// Parses a decimal typed by the user (comma or dot); null when it is not a number.
double? parseQuantity(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// Splits the serial numbers typed one per line (commas also separate); blanks are dropped.
List<String> parseSerials(String text) => [
  for (final s in text.split(RegExp(r'[\n,]')))
    if (s.trim().isNotEmpty) s.trim(),
];

String _fmt(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

class _ReceiveLine {
  _ReceiveLine(this.line, this.remaining)
    : qty = TextEditingController(text: _fmt(remaining));
  final PurchaseOrderLine line;
  final double remaining;
  final TextEditingController qty;
  final lot = TextEditingController();
  final serials = TextEditingController();
  String tracking = 'none';

  void dispose() {
    qty.dispose();
    lot.dispose();
    serials.dispose();
  }
}

/// Dialog that books a goods receipt for the open lines of [po]. It posts the receipt itself, shows
/// backend errors (409/422) inline, and pops the booked [GoodsReceiptDetail] on success.
class ReceiveGoodsDialog extends ConsumerStatefulWidget {
  /// Receives goods for [po].
  const ReceiveGoodsDialog({super.key, required this.po});

  /// The purchase order being received.
  final PurchaseOrderDetail po;

  @override
  ConsumerState<ReceiveGoodsDialog> createState() => _ReceiveGoodsDialogState();
}

class _ReceiveGoodsDialogState extends ConsumerState<ReceiveGoodsDialog> {
  late final List<_ReceiveLine> _rows;
  final _carrier = TextEditingController();
  final _tracking = TextEditingController();
  final _note = TextEditingController();
  final _notes = TextEditingController();
  String? _location;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _rows = [];
    for (final l in widget.po.lines) {
      final remaining =
          (parseQuantity(l.quantity) ?? 0) -
          (parseQuantity(l.quantityReceived) ?? 0);
      if (remaining > 0) _rows.add(_ReceiveLine(l, remaining));
    }
    _loadTracking();
  }

  /// Looks up the tracking mode of each product; lines stay untracked if a lookup fails.
  Future<void> _loadTracking() async {
    final products = ref.read(apiProvider).products;
    for (final r in _rows) {
      try {
        final p = await products.getProduct(id: r.line.productId);
        if (!mounted) return;
        setState(() => r.tracking = p.tracking);
      } catch (_) {
        // The backend still enforces lot and serial numbers and reports what is missing.
      }
    }
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _carrier.dispose();
    _tracking.dispose();
    _note.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Builds the payload, or sets the first validation problem and returns null.
  ReceiveGoodsInput? _build(String warehouseId) {
    final l = context.l10n;
    final lines = <ReceiveGoodsLineInput>[];
    for (final r in _rows) {
      final q = parseQuantity(r.qty.text);
      final name = r.line.productCode;
      if (q == null || q < 0 || q > r.remaining + 1e-9) {
        _error = l.purchReceiveQtyInvalid(name, _fmt(r.remaining));
        return null;
      }
      if (q == 0) continue;
      String? lot;
      List<String>? serials;
      if (r.tracking == 'lot') {
        lot = r.lot.text.trim();
        if (lot.isEmpty) {
          _error = l.purchReceiveLotNeeded(name);
          return null;
        }
      } else if (r.tracking == 'serial') {
        if (q != q.roundToDouble()) {
          _error = l.purchReceiveSerialWhole(name);
          return null;
        }
        serials = parseSerials(r.serials.text);
        if (serials.length != q.round() ||
            serials.toSet().length != serials.length) {
          _error = l.purchReceiveSerialCount(name, q.round());
          return null;
        }
      }
      lines.add(
        ReceiveGoodsLineInput(
          poLineId: r.line.id,
          quantity: r.qty.text.trim().replaceAll(',', '.'),
          lotNumber: lot,
          serialNumbers: serials,
        ),
      );
    }
    if (lines.isEmpty) {
      _error = l.purchReceiveNothing;
      return null;
    }
    String? opt(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    return ReceiveGoodsInput(
      warehouseId: warehouseId,
      locationId: _location!,
      carrier: opt(_carrier),
      trackingNumber: opt(_tracking),
      supplierDeliveryNote: opt(_note),
      notes: opt(_notes),
      lines: lines,
    );
  }

  Future<void> _submit() async {
    final l = context.l10n;
    setState(() => _error = null);
    String? warehouseId;
    for (final w in ref.read(warehousesProvider).value ?? const <Warehouse>[]) {
      if (w.locations.any((x) => x.id == _location)) warehouseId = w.id;
    }
    if (_location == null || warehouseId == null) {
      setState(() => _error = l.purchReceiveLocationNeeded);
      return;
    }
    final input = _build(warehouseId);
    if (input == null) {
      setState(() {});
      return;
    }
    setState(() => _busy = true);
    try {
      final gr = await ref
          .read(apiProvider)
          .purchasing
          .receiveGoods(id: widget.po.id, body: input);
      if (mounted) Navigator.pop(context, gr);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.purchReceiveTitle(widget.po.number)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    key: const ValueKey('receive-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              LocationField(
                label: l.purchReceiveDestination,
                value: _location,
                onChanged: (v) => setState(() => _location = v),
              ),
              const SizedBox(height: 12),
              for (final r in _rows) ...[
                Text(
                  '${r.line.productCode} · ${r.line.productName}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                TextField(
                  key: ValueKey('receive-qty-${r.line.lineNumber}'),
                  controller: r.qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l.purchReceiveQty,
                    helperText: l.purchReceiveRemaining(_fmt(r.remaining)),
                  ),
                ),
                if (r.tracking == 'lot')
                  TextField(
                    key: ValueKey('receive-lot-${r.line.lineNumber}'),
                    controller: r.lot,
                    decoration: InputDecoration(labelText: l.stockLotNumber),
                  ),
                if (r.tracking == 'serial')
                  TextField(
                    key: ValueKey('receive-serials-${r.line.lineNumber}'),
                    controller: r.serials,
                    minLines: 2,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: l.serialNumbers,
                      helperText: l.purchReceiveSerialsHelp,
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              TextField(
                key: const ValueKey('receive-carrier'),
                controller: _carrier,
                decoration: InputDecoration(labelText: l.carrier),
              ),
              TextField(
                key: const ValueKey('receive-tracking'),
                controller: _tracking,
                decoration: InputDecoration(labelText: l.trackingNumber),
              ),
              TextField(
                key: const ValueKey('receive-delivery-note'),
                controller: _note,
                decoration: InputDecoration(labelText: l.purchDeliveryNote),
              ),
              TextField(
                key: const ValueKey('receive-notes'),
                controller: _notes,
                maxLines: 2,
                decoration: InputDecoration(labelText: l.notes),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('receive-cancel'),
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        TutorialTarget(id: 'po-receive-submit', child: FilledButton(
          key: const ValueKey('receive-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l.purchReceiveGoods),
        )),
      ],
    );
  }
}
