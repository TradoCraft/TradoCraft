import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/api.dart';
import '../../app/workspace.dart';
import '../../shared/app_icons.dart';
import '../../shared/decimal_field.dart';
import '../../shared/format.dart';
import '../../shared/photos.dart';
import '../../shared/search_picker.dart';
import 'families_dialog.dart';
import 'packaging_dialog.dart';
import '../../l10n/l10n.dart';
import '../tutorial/targets.dart';

const productTypes = ['purchased', 'manufactured', 'configurable', 'service'];

class ProductsRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// Incremented whenever a product is created or updated from [ProductForm].
final productsRefreshProvider = NotifierProvider<ProductsRefreshNotifier, int>(
  ProductsRefreshNotifier.new,
);

/// Create or edit a product. Returns the saved product, or null when cancelled.
Future<Product?> showProductForm(
  BuildContext context, {
  Product? product,
  PhotoPicker? pickMedia,
}) => showDialog<Product>(
  context: context,
  builder: (_) => ProductForm(product: product, pickMedia: pickMedia),
);

class ProductForm extends ConsumerStatefulWidget {
  const ProductForm({
    super.key,
    this.product,
    this.pickMedia,
    this.asTab = false,
    this.onSaved,
    this.onCancel,
  });
  final Product? product;
  final PhotoPicker? pickMedia;
  final bool asTab;
  final ValueChanged<Product>? onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<ProductForm> createState() => _ProductFormState();
}

class _StagedMedia {
  _StagedMedia(this.photo) : clientId = newClientId();
  final PickedPhoto photo;
  final String clientId;
  String? uploadedId;

  String get filename => photo.filename;
  Uint8List get bytes => photo.bytes;
}

class _ProductFormState extends ConsumerState<ProductForm> {
  late final p = widget.product;
  late final _code = TextEditingController(text: p?.code);
  late final _name = TextEditingController(text: p?.name);
  late final _description = TextEditingController(text: p?.description);
  late final _unit = TextEditingController(text: p?.unit ?? 'pcs');
  late String _vatCategory =
      const {
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
  late bool _nonDiscountable = p?.nonDiscountable ?? false;
  late bool _priceOnRequest = p?.priceOnRequest ?? false;
  late bool? _includedInTurnover = p?.includedInTurnover;
  bool _includedInTurnoverEdited = false;
  late bool _priceIsIndicative = p?.priceIsIndicative ?? false;
  late bool _active = p?.active ?? true;
  late String? _packagingId = p?.packagingCategoryId;
  late final _length = TextEditingController(text: p?.lengthMm?.toString());
  late final _width = TextEditingController(text: p?.widthMm?.toString());
  late final _height = TextEditingController(text: p?.heightMm?.toString());
  late final _weight = TextEditingController(text: p?.weightG?.toString());
  late final _defaultRemark = TextEditingController(
    text: p?.defaultProductionRemark,
  );
  final List<_StagedMedia> _media = [];
  final List<String> _pendingDeletions = [];
  int _defaultMediaIndex = 0;
  Product? _created;
  Product? _copiedFrom;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  late final List<TextEditingController> _trackedControllers = [
    _code,
    _name,
    _description,
    _unit,
    _vatOverride,
    _cost,
    _reorderMin,
    _reorderMax,
    _leadTime,
    _barcode,
    _length,
    _width,
    _height,
    _weight,
    _defaultRemark,
  ];

  @override
  void initState() {
    super.initState();
    for (final c in _trackedControllers) {
      c.addListener(_markDirty);
    }
    if (widget.asTab) {
      TabScope.reportTitle(context, p?.code ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in _trackedControllers) {
      c.removeListener(_markDirty);
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) {
      _dirty = true;
      if (mounted) TabScope.reportDirty(context, true);
    }
  }

  void _setDirtyState(VoidCallback fn) {
    setState(fn);
    _markDirty();
  }

  Future<void> _cancel() async {
    if (widget.onCancel != null) {
      if (_dirty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(c.l10n.unsavedChangesTitle),
            content: Text(c.l10n.unsavedChangesBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(c.l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(c.l10n.discardChanges),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
      widget.onCancel!();
      return;
    }
    final scope = TabScope.maybeOf(context);
    if (widget.asTab && scope != null) {
      await requestCloseTab(context, ref, scope.id);
    } else {
      Navigator.maybePop(context);
    }
  }

  void _copyFrom(Product source) {
    _setDirtyState(() {
      _copiedFrom = source;
      _description.text = source.description;
      _unit.text = source.unit;
      _type = productTypes.contains(source.productType)
          ? source.productType
          : 'purchased';
      _vatCategory =
          const {
            'standard',
            'intermediate',
            'reduced',
            'zero',
          }.contains(source.vatCategory)
          ? source.vatCategory!
          : 'standard';
      _vatOverride.text = source.vatRateOverride != null
          ? number(source.vatRateOverride!)
          : '';
      _tracking = source.tracking;
      final families =
          ref.read(familiesProvider).value ?? const <ProductFamily>[];
      _familyId = families.any((f) => f.id == source.familyId)
          ? source.familyId
          : null;
      _nonDiscountable = source.nonDiscountable;
      _priceOnRequest = source.priceOnRequest;
      _includedInTurnover = source.includedInTurnover;
      _includedInTurnoverEdited = source.includedInTurnover != null;
      _priceIsIndicative = source.priceIsIndicative;
      _active = source.active;
      _cost.text = editableDecimal(source.standardCost);
      _reorderMin.text = editableDecimal(source.reorderMin);
      _reorderMax.text = editableDecimal(source.reorderMax);
      _leadTime.text = source.leadTimeDays?.toString() ?? '';
      _packagingId = source.packagingCategoryId;
      _length.text = source.lengthMm?.toString() ?? '';
      _width.text = source.widthMm?.toString() ?? '';
      _height.text = source.heightMm?.toString() ?? '';
      _weight.text = source.weightG?.toString() ?? '';
      _defaultRemark.text = source.defaultProductionRemark ?? '';
    });
  }

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
      nonDiscountable: _nonDiscountable,
      priceOnRequest: _priceOnRequest,
      includedInTurnover:
          _includedInTurnoverEdited ||
              _includedInTurnover != p?.includedInTurnover
          ? _includedInTurnover
          : null,
      priceIsIndicative: _priceIsIndicative,
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider).products;
      final dio = ref.read(dioProvider);
      final targetId = p?.id ?? _created?.id;
      final clearTurnover =
          _includedInTurnoverEdited && _includedInTurnover == null;
      var saved = clearTurnover
          ? Product.fromJson(
              (await (targetId == null
                      ? dio.post<Map<String, dynamic>>(
                          '/api/v1/products',
                          data: body.toJson()..['included_in_turnover'] = null,
                        )
                      : dio.put<Map<String, dynamic>>(
                          '/api/v1/products/$targetId',
                          data: body.toJson()..['included_in_turnover'] = null,
                        )))
                  .data!,
            )
          : targetId == null
          ? await api.createProduct(body: body)
          : await api.updateProduct(id: targetId, body: body);
      if (p == null) _created = saved;
      if (_pendingDeletions.isNotEmpty || _media.isNotEmpty) {
        final base = '/api/v1/products/${saved.id}/media';
        while (_pendingDeletions.isNotEmpty) {
          final deadId = _pendingDeletions.first;
          try {
            await dio.delete<Object?>('$base/$deadId');
          } on DioException catch (e) {
            if (e.response?.statusCode != 404) rethrow;
          }
          _pendingDeletions.removeAt(0);
        }
        if (_media.isNotEmpty) {
          final chosenIndex = _defaultMediaIndex.clamp(0, _media.length - 1);
          final chosen = _media[chosenIndex];
          for (final item in _media) {
            if (item.uploadedId == null) {
              final res = await uploadPhoto(
                dio,
                base,
                item.photo,
                clientId: item.clientId,
              );
              final data = res.data;
              item.uploadedId =
                  (data is Map<String, dynamic>
                      ? data['id'] as String?
                      : null) ??
                  item.clientId;
            }
          }
          final chosenId = chosen.uploadedId;
          if (chosenId != null) {
            await dio.patch<Object?>(
              '$base/$chosenId',
              data: {'is_default': true},
            );
          }
        }
        saved = await api.getProduct(id: saved.id);
      }
      _dirty = false;
      ref.read(productsRefreshProvider.notifier).bump();
      if (mounted) {
        TabScope.reportDirty(context, false);
        if (widget.onSaved != null) {
          widget.onSaved!(saved);
        } else if (!widget.asTab) {
          Navigator.pop(context, saved);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addMedia() async {
    final picker = widget.pickMedia ?? pickProductMedia;
    try {
      final picked = await picker(context);
      if (picked.isEmpty || !mounted) return;
      _setDirtyState(() {
        _media.addAll([for (final item in picked) _StagedMedia(item)]);
        if (_defaultMediaIndex >= _media.length) _defaultMediaIndex = 0;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    }
  }

  void _removeMedia(int index) {
    _setDirtyState(() {
      final removed = _media.removeAt(index);
      _pendingDeletions.add(removed.uploadedId ?? removed.clientId);
      if (_media.isEmpty) {
        _defaultMediaIndex = 0;
      } else if (index == _defaultMediaIndex) {
        _defaultMediaIndex = 0;
      } else if (index < _defaultMediaIndex) {
        _defaultMediaIndex -= 1;
      }
    });
  }

  static bool _isVideoFilename(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.webm');
  }

  Widget _mediaSection(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(l.productMedia, style: theme.textTheme.labelLarge),
            TextButton.icon(
              key: const ValueKey('product-form-add-media'),
              onPressed: _saving ? null : _addMedia,
              icon: const Icon(AppIcons.addAPhoto),
              label: Text(l.addPictureOrVideo),
            ),
          ],
        ),
        if (_media.isEmpty)
          Text(l.noMedia, style: theme.textTheme.bodySmall)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _media.length; i++)
                SizedBox(
                  key: ValueKey('staged-media-$i'),
                  width: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.1),
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: 120,
                                height: 90,
                                child: _isVideoFilename(_media[i].filename)
                                    ? const Center(
                                        child: Icon(
                                          AppIcons.playCircle,
                                          size: 36,
                                        ),
                                      )
                                    : isSvgBytes(_media[i].bytes)
                                    ? SvgPicture.memory(
                                        _media[i].bytes,
                                        fit: BoxFit.contain,
                                      )
                                    : Image.memory(
                                        _media[i].bytes,
                                        fit: BoxFit.cover,
                                        cacheWidth: 360,
                                        errorBuilder: (_, _, _) => const Center(
                                          child: Icon(AppIcons.brokenImage),
                                        ),
                                      ),
                              ),
                              if (i == _defaultMediaIndex)
                                Positioned(
                                  left: 4,
                                  top: 4,
                                  child: Chip(
                                    key: ValueKey('staged-media-default-$i'),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    avatar: const Icon(
                                      AppIcons.starFilled,
                                      size: 14,
                                    ),
                                    label: Text(l.defaultMedia),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Text(
                        _media[i].filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      Row(
                        children: [
                          if (i != _defaultMediaIndex)
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  key: ValueKey('staged-media-make-default-$i'),
                                  onPressed: _saving
                                      ? null
                                      : () => _setDirtyState(
                                          () => _defaultMediaIndex = i,
                                        ),
                                  child: Text(
                                    l.makeDefault,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                          else
                            const Spacer(),
                          IconButton(
                            key: ValueKey('staged-media-remove-$i'),
                            tooltip: l.delete,
                            icon: const Icon(AppIcons.delete, size: 18),
                            onPressed: _saving ? null : () => _removeMedia(i),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Active packaging categories (plus the product's own, even if it has been deactivated since).
  Widget _packagingField() {
    final all = ref.watch(packagingCategoriesProvider).value ?? const [];
    final options = [
      for (final c in all)
        if (c.active || c.id == _packagingId) c,
    ];
    return DropdownButtonFormField<String?>(
      key: ValueKey('packaging-${_copiedFrom?.id ?? ''}-${options.length}'),
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
      onChanged: (v) => _setDirtyState(() => _packagingId = v),
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
            key: ValueKey('vat-${_copiedFrom?.id ?? ''}'),
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
            onChanged: (v) => _setDirtyState(() => _vatCategory = v!),
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

  List<Widget> _actions(BuildContext context) => [
        TextButton(
          onPressed: _saving ? null : _cancel,
          child: Text(context.l10n.cancel),
        ),
        TutorialTarget(
          id: 'product-form-save',
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(context.l10n.save),
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final titleText = p == null ? context.l10n.newProduct : p!.code;
    final body = _formBody(context);
    final actions = _actions(context);
    if (widget.asTab) {
      return Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      titleText,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  actions[0],
                  const SizedBox(width: 8),
                  actions[1],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: body,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return AlertDialog(
      // The inventory fields make the form taller than a small window or the on-screen keyboard.
      scrollable: true,
      title: Text(titleText),
      content: SizedBox(width: 520, child: body),
      actions: actions,
    );
  }

  Widget _formBody(BuildContext context) {
    const gap = SizedBox(height: 12, width: 12);
    return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (p == null && _created == null) ...[
              SearchPicker<Product>(
                key: const ValueKey('product-copy-from'),
                label: context.l10n.copyFromProduct,
                initial: _copiedFrom,
                display: (item) => '${item.code} · ${item.name}',
                search: (q) async => (await ref
                        .read(apiProvider)
                        .products
                        .listProducts(q: q, limit: 20))
                    .items,
                onSelected: _copyFrom,
              ),
              if (_copiedFrom != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Chip(
                      key: const ValueKey('product-copied-chip'),
                      avatar: const Icon(AppIcons.copy, size: 16),
                      label: Text(
                        context.l10n.copiedFromProduct(_copiedFrom!.code),
                      ),
                    ),
                  ),
                ),
              gap,
            ],
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
                    key: ValueKey('type-${_copiedFrom?.id ?? ''}'),
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
                    onChanged: (v) => _setDirtyState(() => _type = v!),
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
                  child: Builder(
                    builder: (context) {
                      final families =
                          ref.watch(familiesProvider).value ?? <ProductFamily>[];
                      return DropdownButtonFormField<String?>(
                        key: ValueKey('family-${_copiedFrom?.id ?? ''}-${families.length}'),
                        initialValue: families.any((f) => f.id == _familyId)
                            ? _familyId
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: context.l10n.family),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(context.l10n.none),
                          ),
                          for (final f in families)
                            DropdownMenuItem<String?>(
                              value: f.id,
                              child: Text('${f.code} · ${f.name}'),
                            ),
                        ],
                        onChanged: (v) => _setDirtyState(() => _familyId = v),
                      );
                    },
                  ),
                ),
              ],
            ),
            gap,
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.l10n.pricing,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            CheckboxListTile(
              key: const ValueKey('pricing-non-discountable'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(context.l10n.pricingNetHelp),
              value: _nonDiscountable,
              onChanged: (v) =>
                  _setDirtyState(() => _nonDiscountable = v ?? false),
            ),
            CheckboxListTile(
              key: const ValueKey('pricing-on-request'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(context.l10n.pricingOnRequestHelp),
              value: _priceOnRequest,
              onChanged: (v) =>
                  _setDirtyState(() => _priceOnRequest = v ?? false),
            ),
            CheckboxListTile(
              key: const ValueKey('pricing-indicative'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(context.l10n.pricingIndicativeHelp),
              value: _priceIsIndicative,
              onChanged: (v) =>
                  _setDirtyState(() => _priceIsIndicative = v ?? false),
            ),
            gap,
            DropdownButtonFormField<bool?>(
              key: ValueKey('included-in-turnover-${_copiedFrom?.id ?? ''}'),
              initialValue: _includedInTurnover,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: context.l10n.productIncludedInTurnover,
              ),
              hint: Text(context.l10n.productTurnoverUnclassified),
              items: [
                DropdownMenuItem<bool?>(
                  value: null,
                  child: Text(context.l10n.productTurnoverUnclassified),
                ),
                DropdownMenuItem<bool?>(value: true, child: Text(context.l10n.yes)),
                DropdownMenuItem<bool?>(value: false, child: Text(context.l10n.no)),
              ],
              onChanged: (value) => _setDirtyState(() {
                _includedInTurnover = value;
                _includedInTurnoverEdited = true;
              }),
            ),
            gap,
            DropdownButtonFormField<String>(
              key: ValueKey('tracking-${_copiedFrom?.id ?? ''}'),
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
                  : (v) => _setDirtyState(() => _tracking = v!),
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
              onChanged: (v) => _setDirtyState(() => _active = v),
            ),
            if (p == null) ...[gap, _mediaSection(context)],
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
    );
  }
}
