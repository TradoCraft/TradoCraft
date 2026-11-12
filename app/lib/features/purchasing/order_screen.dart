import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/api.dart';
import '../../app/workspace.dart' show TabScope;
import '../../l10n/l10n.dart';
import '../../shared/actions.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../finance/invoice_form.dart';
import 'po_form.dart';
import 'po_lines.dart';
import 'receive_dialog.dart';
import '../tutorial/targets.dart';

/// A purchase order in a workspace tab: header, lines with received quantities, and the actions
/// the status and the user's rights allow. Drafts are editable.
///
/// Goods are received from here: the "receive goods" action opens [ReceiveGoodsDialog] for
/// `approved`, `sent` and `partially_received` orders, and the booked receipts are listed below
/// the lines.
class PurchaseOrderScreen extends ConsumerStatefulWidget {
  /// Shows the purchase order with [id].
  const PurchaseOrderScreen({super.key, required this.id});

  /// The purchase order to show.
  final String id;

  @override
  ConsumerState<PurchaseOrderScreen> createState() =>
      _PurchaseOrderScreenState();
}

class _PurchaseOrderScreenState extends ConsumerState<PurchaseOrderScreen> {
  PurchaseOrderDetail? _po;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  List<GoodsReceiptSummary> _receipts = const [];

  // Draft editing state; non-null `_lines` means the form is open.
  List<PoLineDraft>? _lines;
  Map<String, SupplierProduct> _prices = {};
  DateTime? _expected;
  final _notes = TextEditingController();

  PurchasingClient get _api => ref.read(apiProvider).purchasing;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _notes.dispose();
    for (final d in _lines ?? const <PoLineDraft>[]) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final po = await _api.getOrder(id: widget.id);
      if (!mounted) return;
      _applyLoaded(po);
      await _loadReceipts();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Loads the receipts booked against this order; a failure just leaves the list empty.
  Future<void> _loadReceipts() async {
    try {
      final list = await _api.listOrderReceipts(id: widget.id);
      if (mounted) setState(() => _receipts = list);
    } catch (_) {
      // The list is supplementary; the order itself is still usable.
    }
  }

  /// Opens the receive dialog; on success refreshes the order and offers to open the receipt.
  Future<void> _receive() async {
    final po = _po!;
    final gr = await showDialog<GoodsReceiptDetail>(
      context: context,
      builder: (_) => ReceiveGoodsDialog(po: po),
    );
    if (gr == null || !mounted) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(l.purchReceiptBooked(gr.number)),
        action: SnackBarAction(
          label: l.purchOpenReceipt,
          onPressed: () => router.push('/goods-receipts/${gr.id}'),
        ),
      ),
    );
    await _load();
  }

  /// Opens the new supplier invoice dialog for this order and shows the created invoice.
  Future<void> _createInvoice() async {
    final po = _po!;
    final created = await showNewInvoiceDialog(
      context,
      supplierId: po.supplierId,
      supplierName: po.supplierName,
      orderId: po.id,
      orderNumber: po.number,
    );
    if (created != null && mounted) {
      context.push('/supplier-invoices/${created.id}');
    }
  }

  void _applyLoaded(PurchaseOrderDetail po) {
    TabScope.reportTitle(context, po.number);
    setState(() => _po = po);
  }

  Future<void> _startEdit() async {
    final po = _po!;
    for (final d in _lines ?? const <PoLineDraft>[]) {
      d.dispose();
    }
    setState(() {
      _lines = [for (final l in po.lines) PoLineDraft.fromLine(l)];
      _expected = po.expectedDeliveryDate;
      _notes.text = po.notes;
    });
    try {
      final list = await _api.listSupplierProducts(id: po.supplierId);
      if (mounted) {
        setState(() => _prices = {for (final p in list) p.productId: p});
      }
    } catch (_) {
      // No price list: new lines are simply not pre-filled.
    }
  }

  void _stopEdit() {
    final old = _lines;
    setState(() => _lines = null);
    for (final d in old ?? const <PoLineDraft>[]) {
      d.dispose();
    }
    TabScope.reportDirty(context, false);
  }

  void _dirty() {
    setState(() => _error = null);
    TabScope.reportDirty(context, true);
  }

  Future<void> _save() async {
    final (lines, problem) = buildPoLines(context.l10n, _lines!);
    if (lines == null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final po = await _api.updateOrder(
        id: widget.id,
        body: UpdatePurchaseOrderInput(
          expectedDeliveryDate: _expected,
          notes: _notes.text.trim(),
          lines: lines,
        ),
      );
      if (!mounted) return;
      _applyLoaded(po);
      _stopEdit();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs a lifecycle call; conflicts (409/422) are shown in the banner.
  Future<void> _transition(Future<PurchaseOrderDetail> Function() call) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final po = await call();
      if (mounted) _applyLoaded(po);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelOrder() async {
    final l = context.l10n;
    final number = _po!.number;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.purchCancelOrder),
        content: Text(l.purchCancelOrderConfirm(number)),
        actions: [
          TextButton(
            key: const ValueKey('po-cancel-keep'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.purchKeepOrder),
          ),
          FilledButton(
            key: const ValueKey('po-cancel-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.purchCancelOrder),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _transition(() => _api.cancelOrder(id: widget.id));
  }

  /// The status and receiving actions available to the user.
  List<Widget> _actions(PurchaseOrderDetail s) {
    final l = context.l10n;
    final canWrite = can(ref, 'purchasing.write');
    final canApprove = can(ref, 'purchasing.approve');
    return [
      if (s.status == 'draft' && canWrite)
        OutlinedButton.icon(
          key: const ValueKey('po-edit'),
          onPressed: _busy ? null : _startEdit,
          icon: const Icon(AppIcons.edit),
          label: Text(l.edit),
        ),
      if (s.status == 'draft' && canApprove)
        TutorialTarget(id: 'po-approve', child: FilledButton(
          key: const ValueKey('po-approve'),
          onPressed: _busy
              ? null
              : () => _transition(() => _api.approveOrder(id: widget.id)),
          child: Text(l.purchApprove),
        )),
      if (s.status == 'approved' && canWrite)
        TutorialTarget(id: 'po-send', child: FilledButton(
          key: const ValueKey('po-send'),
          onPressed: _busy
              ? null
              : () => _transition(() => _api.sendOrder(id: widget.id)),
          child: Text(l.send),
        )),
      if (const {'approved', 'sent', 'partially_received'}.contains(s.status) &&
          can(ref, 'purchasing.receipt'))
        TutorialTarget(id: 'po-receive', child: FilledButton(
          key: const ValueKey('po-receive'),
          onPressed: _busy ? null : _receive,
          child: Text(l.purchReceiveGoods),
        )),
      if (const {'partially_received', 'received'}.contains(s.status) &&
          can(ref, 'finance.write'))
        TutorialTarget(id: 'po-create-invoice', child: OutlinedButton(
          key: const ValueKey('po-create-invoice'),
          onPressed: _busy ? null : _createInvoice,
          child: Text(l.finCreateInvoice),
        )),
      if (const {'draft', 'approved', 'sent'}.contains(s.status) && canWrite)
        TextButton(
          key: const ValueKey('po-cancel'),
          onPressed: _busy ? null : _cancelOrder,
          child: Text(l.purchCancelOrder),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final po = _po;
    if (po == null) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error ?? ''),
            TextButton(onPressed: _load, child: Text(l.retry)),
          ],
        ),
      );
    }
    final s = po;
    final editing = _lines != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(s.number, style: Theme.of(context).textTheme.headlineSmall),
            PoStatusChip(status: s.status),
            if (!editing) ..._actions(s),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null)
          MaterialBanner(
            key: const ValueKey('po-banner'),
            content: Text(_error!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _error = null),
                child: Text(l.close),
              ),
            ],
          ),
        if (_loading || _busy) const LinearProgressIndicator(),
        Wrap(
          children: [
            InfoItem(l.purchSupplier, s.supplierName),
            InfoItem(l.purchOrderDate, date(s.orderDate)),
            if (!editing)
              InfoItem(l.purchExpectedDate, date(s.expectedDeliveryDate)),
            InfoItem(l.currency, s.currency),
            InfoItem(l.purchSubtotal, money(s.subtotal, currency: s.currency)),
            InfoItem(l.purchTax, money(s.taxTotal, currency: s.currency)),
            InfoItem(l.total, money(s.total, currency: s.currency)),
            if (!editing) InfoItem(l.notes, s.notes),
          ],
        ),
        if (editing) ...[
          PoDateField(
            label: l.purchExpectedDate,
            value: _expected,
            onChanged: (d) {
              setState(() => _expected = d);
              _dirty();
            },
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('po-notes'),
            controller: _notes,
            decoration: InputDecoration(labelText: l.notes),
            maxLines: 2,
            onChanged: (_) => _dirty(),
          ),
        ],
        const Divider(height: 32),
        Text(l.purchLines, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (editing) ...[
          PoLinesEditor(lines: _lines!, prices: _prices, onChanged: _dirty),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                key: const ValueKey('po-save'),
                onPressed: _busy ? null : _save,
                child: Text(l.save),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const ValueKey('po-edit-cancel'),
                onPressed: _busy ? null : _stopEdit,
                child: Text(l.cancel),
              ),
            ],
          ),
        ] else
          _LinesTable(lines: po.lines, currency: s.currency),
        if (!editing && _receipts.isNotEmpty) ...[
          const Divider(height: 32),
          Text(l.purchReceipts, style: Theme.of(context).textTheme.titleLarge),
          for (final r in _receipts)
            ListTile(
              key: ValueKey('po-receipt-${r.id}'),
              title: Text(r.number),
              subtitle: Text(date(r.receivedDate.toLocal())),
              onTap: () => context.push('/goods-receipts/${r.id}'),
            ),
        ],
      ],
    );
  }
}

class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.lines, required this.currency});
  final List<PurchaseOrderLine> lines;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: [
          const DataColumn(label: Text('#')),
          DataColumn(label: Text(l.product)),
          DataColumn(label: Text(l.quantity), numeric: true),
          DataColumn(label: Text(l.purchQtyReceived), numeric: true),
          DataColumn(label: Text(l.unitPrice), numeric: true),
          DataColumn(label: Text(l.purchLineTotal), numeric: true),
        ],
        rows: [
          for (final line in lines)
            DataRow(
              key: ValueKey('po-line-${line.lineNumber}'),
              cells: [
                DataCell(Text('${line.lineNumber}')),
                DataCell(Text('${line.productCode} · ${line.productName}')),
                DataCell(Text(number(line.quantity))),
                DataCell(
                  Text(
                    number(line.quantityReceived),
                    key: ValueKey('po-received-${line.lineNumber}'),
                  ),
                ),
                DataCell(Text(money(line.unitPrice, currency: currency))),
                DataCell(Text(money(line.lineTotal, currency: currency))),
              ],
            ),
        ],
      ),
    );
  }
}
