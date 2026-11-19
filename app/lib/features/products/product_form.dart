import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../shared/decimal_field.dart';
import '../../shared/format.dart';
import 'families_dialog.dart';
import 'packaging_dialog.dart';
import '../../l10n/l10n.dart';
import '../tutorial/targets.dart';

const productTypes = ['purchased', 'manufactured', 'configurable', 'service'];

/// Create or edit a product. Returns the saved product, or null when cancelled.
Future<Product?> showProductForm(BuildContext context, {Product? product}) =>
    showDialog<Product>(
      context: context,
      builder: (_) => ProductForm(product: product),
    );

class ProductForm extends ConsumerStatefulWidget {
  const ProductForm({super.key, this.product});
  final Product? product;

  @override
  ConsumerState<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<ProductForm> {
  late final p = widget.product;
  late final _code = TextEditingController(text: p?.code);
  late final _name = TextEditingController(text: p?.name);
  late final _description = TextEditingController(text: p?.description);
  late final _unit = TextEditingController(text: p?.unit ?? 'pcs');
  late String _vatCategory = const {
    'standard',
    'intermediate',
    'reduced',
    'zero',
  }.contains(p?.vatCategory)
      ? p!.vatCategory!
      : 'standard';
  late final _vatOverride = TextEditingController(
    text: p?.vatRateOverride != null ? number(p!.vatRateOverride!) : '',
  );
  late String _type = p?.productType ?? 'purchased';
  late String _tracking = p?.tracking ?? 'none';
  late final _cost = DecimalInputController(
    text: editableDecimal(p?.standardCost),
  );
  late final _reorderMin = DecimalInputController(
    text: editableDecimal(p?.reorderMin),
  );
  late final _reorderMax = DecimalInputController(
    text: editableDecimal(p?.reorderMax),
  );
  late final _leadTime = TextEditingController(
    text: p?.leadTimeDays?.toString() ?? '',
  );
  late final _barcode = TextEditingController(text: p?.barcode);
  late String? _familyId = p?.familyId;
  late String _pricing = p?.pricingType ?? 'list';
  late bool _active = p?.active ?? true;
  late String? _packagingId = p?.packagingCategoryId;
  late final _length = TextEditingController(text: p?.lengthMm?.toString());
  late final _width = TextEditingController(text: p?.widthMm?.toString());
  late final _height = TextEditingController(text: p?.heightMm?.toString());
  late final _weight = TextEditingController(text: p?.weightG?.toString());
  late final _defaultRemark = TextEditingController(
    text: p?.defaultProductionRemark,
  );
  String? _error;

  /// A positive whole number, or null when empty; [ok] is false for anything else.
  static (int?, bool) _positive(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return (null, true);
    final v = int.tryParse(t);
    return v != null && v > 0 ? (v, true) : (null, false);
  }

  Future<void> _save() async {
    final overrideText = _vatOverride.text.trim();
    final overrideRate = overrideText.isEmpty
        ? null
        : parseDecimalInput(overrideText);
    final overrideNum = overrideRate == null
        ? null
        : double.tryParse(overrideRate);
    if (_code.text.trim().isEmpty ||
        _name.text.trim().isEmpty ||
        (overrideText.isNotEmpty &&
            (overrideRate == null ||
                overrideNum == null ||
                overrideNum < 0 ||
                overrideNum > 100))) {
      setState(() => _error = context.l10n.codeNameVatRequired);
      return;
    }
    final cost = _cost.decimal;
    final min = _reorderMin.decimal;
    final max = _reorderMax.decimal;
    final lead = _leadTime.text.trim().isEmpty
        ? null
        : int.tryParse(_leadTime.text.trim());
    if ((_cost.text.trim().isNotEmpty && cost == null) ||
        (_reorderMin.text.trim().isNotEmpty && min == null) ||
        (_reorderMax.text.trim().isNotEmpty && max == null) ||
        (_leadTime.text.trim().isNotEmpty && lead == null)) {
      setState(() => _error = context.l10n.stockInvalidNumbers);
      return;
    }
    final (length, lengthOk) = _positive(_length);
    final (width, widthOk) = _positive(_width);
    final (height, heightOk) = _positive(_height);
    final (weight, weightOk) = _positive(_weight);
    if (!(lengthOk && widthOk && heightOk && weightOk)) {
      setState(() => _error = context.l10n.positiveWholeNumbers);
      return;
    }
    final body = ProductInput(
      code: _code.text.trim(),
      name: _name.text.trim(),
      description: _description.text,
      unit: _unit.text.trim(),
      productType: _type,
      vatCategory: _vatCategory,
      vatRateOverride: overrideRate,
      vatRate: overrideRate,
      tracking: _type == 'service' ? 'none' : _tracking,
      familyId: _familyId,
      pricingType: _pricing,
      active: _active,
      standardCost: cost,
      reorderMin: min,
      reorderMax: max,
      leadTimeDays: lead,
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      packagingCategoryId: _packagingId,
      lengthMm: length,
      widthMm: width,
      heightMm: height,
      weightG: weight,
      defaultProductionRemark: _defaultRemark.text.trim(),
    );
    try {
      final api = ref.read(apiProvider).products;
      final saved = p == null
          ? await api.createProduct(body: body)
          : await api.updateProduct(id: p!.id, body: body);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  /// Active packaging categories (plus the product's own, even if it has been deactivated since).
  Widget _packagingField() {
    final all = ref.watch(packagingCategoriesProvider).value ?? const [];
    final options = [
      for (final c in all)
        if (c.active || c.id == _packagingId) c,
    ];
    return DropdownButtonFormField<String?>(
      key: ValueKey('packaging-${options.length}'),
      initialValue: options.any((c) => c.id == _packagingId)
          ? _packagingId
          : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: context.l10n.packagingCategory),
      items: [
        DropdownMenuItem<String?>(value: null, child: Text(context.l10n.none)),
        for (final c in options)
          DropdownMenuItem<String?>(
            value: c.id,
            child: Text('${c.code} · ${c.name}'),
          ),
      ],
      onChanged: (v) => setState(() => _packagingId = v),
    );
  }

  Widget _vatFields(BuildContext context, SizedBox gap) {
    final co = ref.watch(meProvider).value?.company.countryCode ?? '';
    final rates = ref.watch(vatRatesProvider).value ?? const [];
    final overrideText = _vatOverride.text.trim();
    final overrideRate = overrideText.isEmpty
        ? null
        : parseDecimalInput(overrideText);
    final categoryRate = co.isEmpty
        ? p?.vatRate
        : (resolveCountryCategoryRate(
                rates,
                countryCode: co,
                category: _vatCategory,
              ) ??
              p?.vatRate);
    final effectiveRate = overrideRate ?? categoryRate;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _vatCategory,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.l10n.vatCategory),
            items: [
              DropdownMenuItem(
                value: 'standard',
                child: Text(context.l10n.vatCategoryStandard),
              ),
              DropdownMenuItem(
                value: 'intermediate',
                child: Text(context.l10n.vatCategoryIntermediate),
              ),
              DropdownMenuItem(
                value: 'reduced',
                child: Text(context.l10n.vatCategoryReduced),
              ),
              DropdownMenuItem(
                value: 'zero',
                child: Text(context.l10n.vatCategoryZero),
              ),
            ],
            onChanged: (v) => setState(() => _vatCategory = v!),
          ),
        ),
        gap,
        SizedBox(
          width: 150,
          child: TextField(
            key: const ValueKey('product-vat-override'),
            controller: _vatOverride,
            decoration: InputDecoration(
              labelText: context.l10n.vatRateOverride,
              hintText: context.l10n.vatRateOverrideHint,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (effectiveRate != null) ...[
          gap,
          Chip(
            key: const ValueKey('product-resolved-vat'),
            label: Text('${number(effectiveRate)} %'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    return AlertDialog(
      // The inventory fields make the form taller than a small window or the on-screen keyboard.
      scrollable: true,
      title: Text(p == null ? context.l10n.newProduct : p!.code),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _code,
                    decoration: InputDecoration(labelText: context.l10n.code),
                  ),
                ),
                gap,
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: context.l10n.name),
                  ),
                ),
              ],
            ),
            gap,
            TextField(
              controller: _description,
              decoration: InputDecoration(labelText: context.l10n.description),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: context.l10n.type),
                    items: [
                      for (final t in productTypes)
                        DropdownMenuItem(
                          value: t,
                          child: Text(context.l10n.productType(t)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
                gap,
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _unit,
                    decoration: InputDecoration(labelText: context.l10n.unit),
                  ),
                ),
              ],
            ),
            gap,
            _vatFields(context, gap),
            gap,
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _familyId,
                    decoration: InputDecoration(labelText: context.l10n.family),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(context.l10n.none),
                      ),
                      for (final f
                          in ref.watch(familiesProvider).value ??
                              <ProductFamily>[])
                        DropdownMenuItem<String?>(
                          value: f.id,
                          child: Text('${f.code} · ${f.name}'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _familyId = v),
                  ),
                ),
                gap,
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _pricing,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.l10n.pricing,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'list',
                        child: Text(context.l10n.pricingListHelp),
                      ),
                      DropdownMenuItem(
                        value: 'net',
                        child: Text(context.l10n.pricingNetHelp),
                      ),
                      DropdownMenuItem(
                        value: 'indicative',
                        child: Text(context.l10n.pricingIndicativeHelp),
                      ),
                    ],
                    onChanged: (v) => setState(() => _pricing = v!),
                  ),
                ),
              ],
            ),
            DropdownButtonFormField<String>(
              initialValue: _tracking,
              isExpanded: true,
              decoration: InputDecoration(labelText: context.l10n.tracking),
              items: [
                DropdownMenuItem(value: 'none', child: Text(context.l10n.none)),
                DropdownMenuItem(
                  value: 'serial',
                  child: Text(context.l10n.serialNumbers),
                ),
                DropdownMenuItem(
                  value: 'lot',
                  child: Text(context.l10n.stockLotTrackingHelp),
                ),
              ],
              onChanged: _type == 'service'
                  ? null
                  : (v) => setState(() => _tracking = v!),
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: DecimalField(
                    controller: _reorderMin,
                    decoration: InputDecoration(
                      labelText: context.l10n.stockReorderMin,
                    ),
                  ),
                ),
                gap,
                Expanded(
                  child: DecimalField(
                    controller: _reorderMax,
                    decoration: InputDecoration(
                      labelText: context.l10n.stockReorderMax,
                    ),
                  ),
                ),
                gap,
                Expanded(
                  child: TextField(
                    controller: _leadTime,
                    decoration: InputDecoration(
                      labelText: context.l10n.stockLeadTime,
                    ),
                  ),
                ),
              ],
            ),
            gap,
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _barcode,
                    decoration: InputDecoration(
                      labelText: context.l10n.stockBarcode,
                    ),
                  ),
                ),
                // Cost is only offered to people who may see it (the server also enforces it).
                if (ref
                        .watch(meProvider)
                        .value
                        ?.permissions
                        .contains('inventory.cost') ??
                    false) ...[
                  gap,
                  Expanded(
                    child: DecimalField(
                      controller: _cost,
                      decoration: InputDecoration(
                        labelText: context.l10n.stockStandardCost,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            gap,
            _packagingField(),
            gap,
            Row(
              children: [
                for (final (i, f) in [
                  (_length, context.l10n.lengthMm),
                  (_width, context.l10n.widthMm),
                  (_height, context.l10n.heightMm),
                  (_weight, context.l10n.weightG),
                ].indexed) ...[
                  if (i > 0) gap,
                  Expanded(
                    child: TextField(
                      controller: f.$1,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: f.$2),
                    ),
                  ),
                ],
              ],
            ),
            gap,
            TextField(
              key: const ValueKey('default-production-remark'),
              controller: _defaultRemark,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: context.l10n.defaultProductionRemark,
                helperText: context.l10n.remarkProductionHelp,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.active),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TutorialTarget(
          id: 'product-form-save',
          child: FilledButton(onPressed: _save, child: Text(context.l10n.save)),
        ),
      ],
    );
  }
}
