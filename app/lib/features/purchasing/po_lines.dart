import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';

/// The localized caption of a purchase order [status].
String poStatusLabel(AppLocalizations l, String status) => switch (status) {
  'draft' => l.purchStatusDraft,
  'approved' => l.purchStatusApproved,
  'sent' => l.purchStatusSent,
  'partially_received' => l.purchStatusPartial,
  'received' => l.purchStatusReceived,
  'cancelled' => l.purchStatusCancelled,
  _ => status,
};

/// Status as text plus colour and icon, so the state never relies on colour alone.
class PoStatusChip extends StatelessWidget {
  /// Shows [status] (`draft`, `approved`, ...).
  const PoStatusChip({super.key, required this.status});

  /// The backend status value.
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      'draft' => (Colors.blueGrey, Icons.edit_note),
      'approved' => (Colors.blue, Icons.check_circle_outline),
      'sent' => (Colors.indigo, Icons.send),
      'partially_received' => (Colors.orange, Icons.inventory_2_outlined),
      'received' => (Colors.green, Icons.done_all),
      'cancelled' => (Colors.red, Icons.cancel_outlined),
      _ => (Colors.grey, Icons.help_outline),
    };
    return Chip(
      key: ValueKey('po-status-$status'),
      avatar: Icon(icon, size: 16, color: color.shade800),
      label: Text(
        poStatusLabel(context.l10n, status),
        style: TextStyle(color: color.shade800, fontWeight: FontWeight.w600),
      ),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.4)),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Editable state of one purchase order line.
class PoLineDraft {
  /// Creates a draft line, optionally for an existing product.
  PoLineDraft({
    this.productId,
    this.label = '',
    this.supplierCode = '',
    this.description = '',
    String quantity = '',
    String unitPrice = '',
  }) : qty = TextEditingController(text: quantity),
       price = TextEditingController(text: unitPrice);

  /// Starts from a stored [line].
  factory PoLineDraft.fromLine(PurchaseOrderLine line) => PoLineDraft(
    productId: line.productId,
    label: '${line.productCode} · ${line.productName}',
    supplierCode: line.supplierProductCode,
    description: line.description,
    quantity: trimDecimal(line.quantity),
    unitPrice: trimDecimal(line.unitPrice),
  );

  /// The chosen product, null until one is picked.
  String? productId;

  /// Display text of the product.
  String label;

  /// The supplier's article code, kept from the price list or the stored line.
  String supplierCode;

  /// Free line description kept from the stored line.
  String description;

  /// Quantity field.
  final TextEditingController qty;

  /// Unit price field.
  final TextEditingController price;

  /// Releases the controllers.
  void dispose() {
    qty.dispose();
    price.dispose();
  }
}

/// Drops trailing zeros of a decimal string (`12.5000` -> `12.5`).
String trimDecimal(String v) =>
    v.contains('.') ? v.replaceFirst(RegExp(r'\.?0+$'), '') : v;

/// Validates [lines] like the backend does and returns the API lines or a message.
(List<NewPoLineInput>?, String?) buildPoLines(
  AppLocalizations l,
  List<PoLineDraft> lines,
) {
  if (lines.isEmpty) return (null, l.purchNeedLine);
  final out = <NewPoLineInput>[];
  for (final d in lines) {
    if (d.productId == null) return (null, l.purchPickProduct);
    final q = parseDecimalInput(d.qty.text);
    if (q == null || double.parse(q) <= 0 || _scale(q) > 4) {
      return (null, l.purchLineQtyInvalid);
    }
    final p = parseDecimalInput(d.price.text);
    if (p == null || double.parse(p) < 0 || _scale(p) > 4) {
      return (null, l.purchLinePriceInvalid);
    }
    out.add(
      NewPoLineInput(
        productId: d.productId!,
        quantity: q,
        unitPrice: p,
        supplierProductCode: d.supplierCode,
        description: d.description,
      ),
    );
  }
  return (out, null);
}

int _scale(String v) => v.contains('.') ? v.split('.').last.length : 0;

/// The lines table of a draft purchase order: pick products, set quantity and price.
class PoLinesEditor extends ConsumerStatefulWidget {
  /// Edits [lines] in place; [prices] holds the supplier's price list per product id.
  const PoLinesEditor({
    super.key,
    required this.lines,
    required this.prices,
    required this.onChanged,
    this.onPriceDefaults,
  });

  /// The lines being edited.
  final List<PoLineDraft> lines;

  /// Price list entries of the chosen supplier, by product id.
  final Map<String, SupplierProduct> prices;

  /// Called after every change (add, remove, typing).
  final VoidCallback onChanged;

  /// Called with the price list entry used to default a newly picked product.
  final void Function(SupplierProduct entry)? onPriceDefaults;

  @override
  ConsumerState<PoLinesEditor> createState() => _PoLinesEditorState();
}

class _PoLinesEditorState extends ConsumerState<PoLinesEditor> {
  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  void _pick(PoLineDraft d, Product p) {
    d.productId = p.id;
    d.label = '${p.code} · ${p.name}';
    final entry = widget.prices[p.id];
    if (entry != null) {
      d.price.text = trimDecimal(entry.unitPrice);
      d.supplierCode = entry.supplierProductCode;
      widget.onPriceDefaults?.call(entry);
    }
    if (d.qty.text.trim().isEmpty) d.qty.text = '1';
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: widget.lines[i].productId != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            widget.lines[i].label,
                            key: ValueKey('po-line-label-$i'),
                          ),
                        )
                      : SearchPicker<Product>(
                          key: ValueKey('po-line-product-$i'),
                          label: l.product,
                          display: (p) => '${p.code} · ${p.name}',
                          search: (q) async =>
                              (await ref
                                      .read(apiProvider)
                                      .products
                                      .listProducts(q: q, limit: 20))
                                  .items,
                          onSelected: (p) => _pick(widget.lines[i], p),
                        ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: ValueKey('po-line-qty-$i'),
                    controller: widget.lines[i].qty,
                    decoration: InputDecoration(labelText: l.quantity),
                    onChanged: (_) => _changed(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: ValueKey('po-line-price-$i'),
                    controller: widget.lines[i].price,
                    decoration: InputDecoration(labelText: l.unitPrice),
                    onChanged: (_) => _changed(),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      _lineTotal(widget.lines[i]),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('po-line-remove-$i'),
                  tooltip: l.remove,
                  icon: const Icon(AppIcons.delete),
                  onPressed: () {
                    widget.lines.removeAt(i).dispose();
                    _changed();
                  },
                ),
              ],
            ),
          ),
        TextButton.icon(
          key: const ValueKey('po-line-add'),
          onPressed: () {
            widget.lines.add(PoLineDraft());
            _changed();
          },
          icon: const Icon(AppIcons.add),
          label: Text(l.purchAddLine),
        ),
      ],
    );
  }

  String _lineTotal(PoLineDraft d) {
    final q = double.tryParse(parseDecimalInput(d.qty.text) ?? '');
    final p = double.tryParse(parseDecimalInput(d.price.text) ?? '');
    return q == null || p == null ? '' : money((q * p).toStringAsFixed(2));
  }
}
