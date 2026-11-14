import 'package:material_ui/material_ui.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/app_icons.dart';
import '../../shared/format.dart';

/// Supplier invoice statuses in lifecycle order, used by the filter chips.
const invoiceStatuses = ['draft', 'matched', 'disputed', 'approved', 'paid'];

/// The localized caption of a supplier invoice [status].
String invoiceStatusLabel(AppLocalizations l, String status) =>
    switch (status) {
      'draft' => l.finStatusDraft,
      'matched' => l.finStatusMatched,
      'disputed' => l.finStatusDisputed,
      'approved' => l.finStatusApproved,
      'paid' => l.finStatusPaid,
      _ => status,
    };

/// The localized caption of a match line [status].
String lineStatusLabel(AppLocalizations l, LineStatus status) =>
    switch (status) {
      LineStatus.ok => l.finMatchOk,
      LineStatus.notReceived => l.finMatchNotReceived,
      LineStatus.overInvoiced => l.finMatchOverInvoiced,
      LineStatus.priceVariance => l.finMatchPriceVariance,
      LineStatus.noPoLine => l.finMatchNoPoLine,
      LineStatus.$unknown => '?',
    };

Widget _chip(Key key, MaterialColor color, IconData icon, String text) => Chip(
  key: key,
  avatar: Icon(icon, size: 16, color: color.shade800),
  label: Text(
    text,
    style: TextStyle(color: color.shade800, fontWeight: FontWeight.w600),
  ),
  backgroundColor: color.withValues(alpha: 0.12),
  side: BorderSide(color: color.withValues(alpha: 0.4)),
  visualDensity: VisualDensity.compact,
);

/// Invoice status as text plus colour and icon, so the state never relies on colour alone.
class InvoiceStatusChip extends StatelessWidget {
  /// Shows [status] (`draft`, `matched`, ...).
  const InvoiceStatusChip({super.key, required this.status});

  /// The backend status value.
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      'draft' => (Colors.blueGrey, Icons.edit_note),
      'matched' => (Colors.teal, Icons.rule),
      'disputed' => (Colors.red, Icons.report_problem_outlined),
      'approved' => (Colors.blue, Icons.check_circle_outline),
      'paid' => (Colors.green, Icons.paid_outlined),
      _ => (Colors.grey, Icons.help_outline),
    };
    return _chip(
      ValueKey('inv-status-$status'),
      color,
      icon,
      invoiceStatusLabel(context.l10n, status),
    );
  }
}

/// Match status of one invoice line (ok, not received, ...) as text, icon and colour.
class LineStatusChip extends StatelessWidget {
  /// Shows [status]; [chipKey] makes the chip findable per line.
  const LineStatusChip({super.key, required this.status, this.chipKey});

  /// The line's first problem, or ok.
  final LineStatus status;

  /// Key of the chip itself.
  final Key? chipKey;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      LineStatus.ok => (Colors.green, Icons.check_circle_outline),
      LineStatus.notReceived => (Colors.red, Icons.inventory_2_outlined),
      LineStatus.overInvoiced => (Colors.red, Icons.trending_up),
      LineStatus.priceVariance => (Colors.orange, Icons.price_change_outlined),
      LineStatus.noPoLine => (Colors.orange, Icons.link_off),
      LineStatus.$unknown => (Colors.grey, Icons.help_outline),
    };
    return _chip(
      chipKey ?? ValueKey('inv-line-chip-${status.json}'),
      color,
      icon,
      lineStatusLabel(context.l10n, status),
    );
  }
}

/// A validated-input draft of one invoice line (text fields, plus the order line it came from).
class InvLineDraft {
  /// Creates a draft line; free-text lines have no [poLineId].
  InvLineDraft({
    this.poLineId,
    this.productId,
    String description = '',
    String quantity = '',
    String unitPrice = '',
    String vatRate = '',
  }) : desc = TextEditingController(text: description),
       qty = TextEditingController(text: quantity),
       price = TextEditingController(text: unitPrice),
       vat = TextEditingController(text: vatRate);

  /// Starts from a stored [line].
  factory InvLineDraft.fromLine(InvoiceLine line) => InvLineDraft(
    poLineId: line.purchaseOrderLineId,
    productId: line.productId,
    description: line.description,
    quantity: _trim(line.quantity),
    unitPrice: _trim(line.unitPrice),
    vatRate: _trim(line.vatRate),
  );

  /// The purchase order line this invoice line is matched against, if any.
  final String? poLineId;

  /// The product of that order line, if any.
  final String? productId;

  /// Description field.
  final TextEditingController desc;

  /// Quantity field.
  final TextEditingController qty;

  /// Unit price field.
  final TextEditingController price;

  /// VAT rate field (percent).
  final TextEditingController vat;

  /// Releases the controllers.
  void dispose() {
    desc.dispose();
    qty.dispose();
    price.dispose();
    vat.dispose();
  }
}

String _trim(String v) =>
    v.contains('.') ? v.replaceFirst(RegExp(r'\.?0+$'), '') : v;

int _scale(String v) => v.contains('.') ? v.split('.').last.length : 0;

/// Validates [lines] like the backend does and returns the API lines or a message.
(List<InvoiceLineInput>?, String?) buildInvoiceLines(
  AppLocalizations l,
  List<InvLineDraft> lines,
) {
  if (lines.isEmpty) return (null, l.purchNeedLine);
  final out = <InvoiceLineInput>[];
  for (final d in lines) {
    final description = d.desc.text.trim();
    if (d.poLineId == null && description.isEmpty) {
      return (null, l.finLineDescriptionRequired);
    }
    final q = parseDecimalInput(d.qty.text);
    if (q == null || double.parse(q) <= 0 || _scale(q) > 4) {
      return (null, l.purchLineQtyInvalid);
    }
    final p = parseDecimalInput(d.price.text);
    if (p == null || double.parse(p) < 0 || _scale(p) > 4) {
      return (null, l.purchLinePriceInvalid);
    }
    String? v;
    if (d.vat.text.trim().isNotEmpty) {
      v = parseDecimalInput(d.vat.text);
      if (v == null ||
          double.parse(v) < 0 ||
          double.parse(v) > 100 ||
          _scale(v) > 2) {
        return (null, l.finVatInvalid);
      }
    }
    out.add(
      InvoiceLineInput(
        purchaseOrderLineId: d.poLineId,
        productId: d.productId,
        description: description.isEmpty ? null : description,
        quantity: q,
        unitPrice: p,
        vatRate: v,
      ),
    );
  }
  return (out, null);
}

/// Editable rows for invoice lines: description, quantity, unit price and VAT rate.
class InvoiceLinesEditor extends StatelessWidget {
  /// Edits [lines] in place; [onChanged] runs after every change (rows added, removed or typed).
  const InvoiceLinesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
  });

  /// The draft lines.
  final List<InvLineDraft> lines;

  /// Called after any change.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    key: ValueKey('inv-line-desc-$i'),
                    controller: lines[i].desc,
                    decoration: InputDecoration(labelText: l.description),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: TextField(
                    key: ValueKey('inv-line-qty-$i'),
                    controller: lines[i].qty,
                    decoration: InputDecoration(labelText: l.quantity),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    key: ValueKey('inv-line-price-$i'),
                    controller: lines[i].price,
                    decoration: InputDecoration(labelText: l.unitPrice),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: ValueKey('inv-line-vat-$i'),
                    controller: lines[i].vat,
                    decoration: InputDecoration(labelText: l.vatPercent),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  key: ValueKey('inv-line-remove-$i'),
                  tooltip: l.delete,
                  icon: const Icon(AppIcons.delete),
                  onPressed: () {
                    lines.removeAt(i).dispose();
                    onChanged();
                  },
                ),
              ],
            ),
          ),
        TextButton.icon(
          key: const ValueKey('inv-add-line'),
          icon: const Icon(AppIcons.add),
          label: Text(l.purchAddLine),
          onPressed: () {
            lines.add(InvLineDraft());
            onChanged();
          },
        ),
      ],
    );
  }
}
