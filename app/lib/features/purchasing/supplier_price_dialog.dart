import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../l10n/l10n.dart';
import '../../shared/format.dart';
import '../../shared/search_picker.dart';
import '../tutorial/targets.dart';

/// Shows the dialog that adds a product to the price list of [supplier], or updates [existing].
/// Returns true when saved.
Future<bool?> showSupplierPriceDialog(
  BuildContext context, {
  required Supplier supplier,
  SupplierProduct? existing,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _PriceDialog(supplier: supplier, existing: existing),
);

class _PriceDialog extends ConsumerStatefulWidget {
  const _PriceDialog({required this.supplier, this.existing});
  final Supplier supplier;
  final SupplierProduct? existing;

  @override
  ConsumerState<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends ConsumerState<_PriceDialog> {
  late final _code = TextEditingController(
    text: widget.existing?.supplierProductCode ?? '',
  );
  late final _name = TextEditingController(
    text: widget.existing?.supplierProductName ?? '',
  );
  late final _price = TextEditingController(
    text: widget.existing == null ? '' : number(widget.existing!.unitPrice),
  );
  late final _currency = TextEditingController(
    text: widget.existing?.currency ?? widget.supplier.currency,
  );
  late final _moq = TextEditingController(
    text: widget.existing == null ? '1' : number(widget.existing!.moq),
  );
  late final _lead = TextEditingController(
    text: '${widget.existing?.leadTimeDays ?? 0}',
  );
  late bool _preferred = widget.existing?.isPreferred ?? false;
  String? _productId;
  String? _productText;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_code, _name, _price, _currency, _moq, _lead]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final productId = widget.existing?.productId ?? _productId;
    final price = parseDecimalInput(_price.text);
    final moq = parseDecimalInput(_moq.text);
    final lead = int.tryParse(_lead.text.trim());
    final cur = _currency.text.trim();
    String? problem;
    if (productId == null) {
      problem = l.purchPickProduct;
    } else if (price == null) {
      problem = l.purchPriceInvalid;
    } else if (moq == null) {
      problem = l.purchMoqInvalid;
    } else if (lead == null || lead < 0) {
      problem = l.purchLeadInvalid;
    } else if (cur.length != 3) {
      problem = l.purchCurrencyInvalid;
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .purchasing
          .setSupplierProduct(
            id: widget.supplier.id,
            productId: productId!,
            body: SetSupplierProductInput(
              supplierProductCode: _code.text.trim(),
              supplierProductName: _name.text.trim(),
              unitPrice: price!,
              currency: cur.toUpperCase(),
              moq: moq,
              leadTimeDays: lead,
              isPreferred: _preferred,
            ),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e);
          _busy = false;
        });
      }
    }
  }

  Widget _field(
    String key,
    TextEditingController c,
    String label, {
    double width = 200,
  }) => SizedBox(
    width: width,
    child: TextField(
      key: ValueKey('price-$key'),
      controller: c,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final existing = widget.existing;
    return AlertDialog(
      title: Text(existing == null ? l.purchAddProduct : l.purchEditPrice),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (existing != null)
                Text(
                  '${existing.productCode} · ${existing.productName}',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              else
                SearchPicker<Product>(
                  key: const ValueKey('price-product'),
                  label: l.product,
                  display: (p) => '${p.code} · ${p.name}',
                  search: (q) async =>
                      (await ref
                              .read(apiProvider)
                              .products
                              .listProducts(q: q, limit: 20))
                          .items,
                  onSelected: (p) {
                    _productId = p.id;
                    _productText = '${p.code} · ${p.name}';
                  },
                  onTextChanged: (t) {
                    if (t != _productText) _productId = null;
                  },
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _field('code', _code, l.purchSupplierArticleCode),
                  _field('name', _name, l.purchSupplierArticleName),
                  _field('price', _price, l.unitPrice, width: 140),
                  _field('currency', _currency, l.currency, width: 90),
                  _field('moq', _moq, l.purchMoq, width: 120),
                  _field('lead', _lead, l.purchLeadTimeDays, width: 140),
                ],
              ),
              SwitchListTile(
                key: const ValueKey('price-preferred'),
                contentPadding: EdgeInsets.zero,
                title: Text(l.purchPreferred),
                value: _preferred,
                onChanged: (v) => setState(() => _preferred = v),
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
        TutorialTarget(id: 'supplier-price-save', child: FilledButton(
          key: const ValueKey('price-save'),
          onPressed: _busy ? null : _save,
          child: Text(l.save),
        )),
      ],
    );
  }
}
