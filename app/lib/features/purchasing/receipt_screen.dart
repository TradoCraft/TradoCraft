import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/format.dart';

/// Read-only goods receipt: header, received lines with their lot, and a link to the order.
///
/// The API does not return the serial numbers booked on a receipt line, so only lots are shown.
class GoodsReceiptScreen extends ConsumerStatefulWidget {
  /// Shows the goods receipt with [id].
  const GoodsReceiptScreen({super.key, required this.id});

  /// The goods receipt to show.
  final String id;

  @override
  ConsumerState<GoodsReceiptScreen> createState() => _GoodsReceiptScreenState();
}

class _GoodsReceiptScreenState extends ConsumerState<GoodsReceiptScreen> {
  GoodsReceiptDetail? _gr;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final gr = await ref
          .read(apiProvider)
          .purchasing
          .getReceipt(id: widget.id);
      if (!mounted) return;
      TabScope.reportTitle(context, gr.number);
      setState(() => _gr = gr);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final gr = _gr;
    if (gr == null) {
      if (_error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, key: const ValueKey('gr-error')),
              TextButton(
                key: const ValueKey('gr-retry'),
                onPressed: _load,
                child: Text(l.retry),
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(gr.number, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Wrap(
          children: [
            InfoItem(l.purchSupplier, gr.supplierName),
            InfoItem(l.purchReceivedDate, date(gr.receivedDate.toLocal())),
            if (gr.carrier.isNotEmpty) InfoItem(l.carrier, gr.carrier),
            if (gr.trackingNumber.isNotEmpty)
              InfoItem(l.trackingNumber, gr.trackingNumber),
            if (gr.supplierDeliveryNote.isNotEmpty)
              InfoItem(l.purchDeliveryNote, gr.supplierDeliveryNote),
            if (gr.notes.isNotEmpty) InfoItem(l.notes, gr.notes),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('gr-open-po'),
            onPressed: () =>
                context.push('/purchase-orders/${gr.purchaseOrderId}'),
            child: Text('${l.purchOpenOrder} ${gr.purchaseOrderNumber}'),
          ),
        ),
        const Divider(height: 32),
        Text(l.purchLines, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              DataColumn(label: Text(l.product)),
              DataColumn(label: Text(l.quantity), numeric: true),
              DataColumn(label: Text(l.stockLot)),
            ],
            rows: [
              for (final line in gr.lines)
                DataRow(
                  key: ValueKey('gr-line-${line.id}'),
                  cells: [
                    DataCell(Text('${line.productCode} · ${line.productName}')),
                    DataCell(Text(number(line.quantityReceived))),
                    DataCell(Text(line.lotNumber ?? '')),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
