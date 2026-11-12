import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import 'po_lines.dart';

/// The quantities typed or ticked in a [SupplierGoodsPicker], one text field per product id.
///
/// A row counts as chosen when its quantity parses to a number above zero.
class GoodsSelection {
  final Map<String, TextEditingController> _qty = {};

  /// The quantity field of [productId], created on first use.
  TextEditingController qty(String productId) =>
      _qty.putIfAbsent(productId, TextEditingController.new);

  /// Whether [productId] has a quantity above zero.
  bool isChosen(String productId) => _positive(_qty[productId]?.text ?? '');

  /// Whether anything at all is chosen.
  bool get hasAny => _qty.values.any((c) => _positive(c.text));

  /// Empties every quantity.
  void clear() {
    for (final c in _qty.values) {
      c.clear();
    }
  }

  /// Releases the controllers.
  void dispose() {
    for (final c in _qty.values) {
      c.dispose();
    }
    _qty.clear();
  }
}

bool _positive(String text) {
  final q = double.tryParse(parseDecimalInput(text) ?? '');
  return q != null && q > 0;
}

/// The quantity a tick starts with: the minimum order quantity when it is above zero, else 1.
String tickQuantity(SupplierProduct entry) {
  final moq = double.tryParse(entry.moq);
  return moq != null && moq > 0 ? trimDecimal(entry.moq) : '1';
}

/// Purchase order line drafts for every product of [entries] with a non-blank quantity.
///
/// The drafts own new controllers; the caller disposes them. Price and supplier article code
/// come from the price list entry.
List<PoLineDraft> selectedGoodsLines(
  List<SupplierProduct> entries,
  GoodsSelection selection,
) => [
  for (final e in entries)
    if (selection.qty(e.productId).text.trim().isNotEmpty)
      PoLineDraft(
        productId: e.productId,
        label: '${e.productCode} · ${e.productName}',
        supplierCode: e.supplierProductCode,
        quantity: selection.qty(e.productId).text,
        unitPrice: trimDecimal(e.unitPrice),
      ),
];

/// The goods a supplier offers, as a filterable list with a checkbox and a quantity per row.
///
/// Ticking a box fills the quantity with the minimum order quantity (or 1); typing a quantity
/// above zero ticks the box; unticking or clearing the quantity drops the line. A quantity below
/// the minimum order quantity is flagged but allowed, because the API does not enforce it.
class SupplierGoodsPicker extends StatefulWidget {
  /// Lists [entries] (the supplier's price list); [selection] holds the quantities.
  const SupplierGoodsPicker({
    super.key,
    required this.entries,
    required this.selection,
    required this.onChanged,
    this.maxHeight = 320,
  });

  /// The supplier's price list entries.
  final List<SupplierProduct> entries;

  /// Where the chosen quantities live.
  final GoodsSelection selection;

  /// Called after every tick or typed quantity.
  final VoidCallback onChanged;

  /// Height of the scrolling list area.
  final double maxHeight;

  @override
  State<SupplierGoodsPicker> createState() => _SupplierGoodsPickerState();
}

class _SupplierGoodsPickerState extends State<SupplierGoodsPicker> {
  String _filter = '';

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _tick(SupplierProduct e, bool on) {
    widget.selection.qty(e.productId).text = on ? tickQuantity(e) : '';
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (widget.entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(l.purchGoodsEmpty, key: const ValueKey('po-goods-empty')),
      );
    }
    final n = _filter.trim().toLowerCase();
    final shown = [
      for (final e in widget.entries)
        if (n.isEmpty ||
            '${e.productCode} ${e.productName} ${e.supplierProductCode} ${e.supplierProductName}'
                .toLowerCase()
                .contains(n))
          e,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          key: const ValueKey('po-goods-filter'),
          decoration: InputDecoration(
            labelText: l.purchGoodsFilter,
            prefixIcon: const Icon(Icons.search),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l.purchGoodsNoMatch,
                    key: const ValueKey('po-goods-nomatch'),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _row(context, shown[i]),
                ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, SupplierProduct e) {
    final l = context.l10n;
    final ctrl = widget.selection.qty(e.productId);
    final chosen = widget.selection.isChosen(e.productId);
    final q = double.tryParse(parseDecimalInput(ctrl.text) ?? '');
    final moq = double.tryParse(e.moq);
    final below = chosen && moq != null && q! < moq;
    final parts = [
      if (e.supplierProductCode.isNotEmpty) e.supplierProductCode,
      money(e.unitPrice, currency: e.currency),
      l.purchMoqValue(number(e.moq)),
    ];
    return Padding(
      key: ValueKey('po-goods-row-${e.productId}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            key: ValueKey('po-goods-check-${e.productId}'),
            value: chosen,
            onChanged: (v) => _tick(e, v ?? false),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${e.productCode} · ${e.productName}'),
                  Text(
                    parts.join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (below)
                    Text(
                      l.purchGoodsBelowMoq(number(e.moq)),
                      key: ValueKey('po-goods-moq-warning-${e.productId}'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              key: ValueKey('po-goods-qty-${e.productId}'),
              controller: ctrl,
              decoration: InputDecoration(labelText: l.quantity, isDense: true),
              onChanged: (_) => _changed(),
            ),
          ),
        ],
      ),
    );
  }
}
